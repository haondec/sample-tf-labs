#!/usr/bin/env bash
set -euo pipefail

# ============================
# Probe Host Setup Script
# - Builds + installs Rust probe app
# - Configures systemd service with capabilities
# - Configures AppConfig env (poll interval default 60s)
# Edit the variables in "USER CONFIG" section below before running.
# ============================

#########################
## USER CONFIG (edit) ##
#########################
# Git repo containing the probe-rust code
LATENCY_PROBE_GIT_REPO="${LATENCY_PROBE_GIT_REPO:-https://github.com/haondec/latency-probe}"
LATENCY_PROBE_VERSION="${LATENCY_PROBE_VERSION:-v0.0.1}"
LATENCY_PROBE_BRANCH="${LATENCY_PROBE_BRANCH:-main}"

# Install location
LATENCY_PROBE_INSTALL_DIR="${LATENCY_PROBE_INSTALL_DIR:-/opt/latency-probe}"
LATENCY_PROBE_BIN_PATH="${LATENCY_PROBE_BIN_PATH:-/usr/local/bin/latency-probe}"

# AppConfig identifiers (the Rust app will use AWS SDK to talk to AppConfigData)
LATENCY_PROBE_APP_ID="${LATENCY_PROBE_APP_ID:-latency-probe-app-id}"         # replace with your AppConfig application id
LATENCY_PROBE_ENV_ID="${LATENCY_PROBE_ENV_ID:-prod}"                         # replace with your AppConfig environment id
LATENCY_PROBE_PROFILE_ID="${LATENCY_PROBE_PROFILE_ID:-targets}"              # replace with your AppConfig configuration profile id
LATENCY_PROBE_AWS_REGION="${LATENCY_PROBE_AWS_REGION:-us-east-1}"

# # Poll interval (seconds) for AppConfig (your request: reload every 1 minute)
LATENCY_PROBE_APP_CONFIG_POLL_INTERVAL_SECONDS="${LATENCY_PROBE_APP_CONFIG_POLL_INTERVAL_SECONDS:-60}"

# Probe user and group
LATENCY_PROBE_USER="${LATENCY_PROBE_USER:-probe}"
LATENCY_PROBE_GROUP="${LATENCY_PROBE_GROUP:-probe}"

# Systemd unit name
LATENCY_PROBE_SERVICE_NAME="${LATENCY_PROBE_SERVICE_NAME:-latency-probe.service}"

#########################
## end USER CONFIG     ##
#########################

echo "=== Probe Host Setup Script ==="
echo "Install dir: $LATENCY_PROBE_INSTALL_DIR"
echo "Git repo: $LATENCY_PROBE_GIT_REPO (branch $LATENCY_PROBE_BRANCH)"
# echo "AppConfig (APP_ID/ENV/PROFILE): $APP_ID / $ENV_ID / $PROFILE_ID"
# echo "AWS Region: $AWS_REGION"
# echo "AppConfig poll interval: ${LATENCY_PROBE_APP_CONFIG_POLL_INTERVAL_SECONDS}s"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. sudo required."
  exit 1
fi

# Detect distro (Debian/Ubuntu vs Amazon Linux / CentOS)
OS=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=${ID}
fi
echo "Detected OS: $OS"

install_packages_debian() {
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential git pkg-config libssl-dev ca-certificates \
    libclang-dev llvm clang python3 python3-pip iproute2 unzip \
    jq libcap2-bin sudo curl wget systemd
}

install_packages_amzn() {
  # Amazon Linux 2 or CentOS
  yum update -y
  yum groupinstall -y "Development Tools" || true
  yum install -y git openssl-devel libffi-devel python3 python3-pip jq which libcap unzip sudo curl wget systemd
  yum install -y libcap
  # remove awscli
  yum remove awscli
}

install_aws_cli() {
  if ! command -v aws >/dev/null 2>&1; then
    echo "Installing awscli"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf awscliv2.zip aws
  fi
}

echo "==> Installing OS packages..."
case "$OS" in
  ubuntu|debian)
    install_packages_debian
    ;;
  amzn|amzn2|centos)
    install_packages_amzn
    ;;
  *)
    # Try apt by default
    echo "Unknown OS $OS — attempting apt install (may fail)."
    install_packages_debian || true
    ;;
esac

# create probe user if not exists
if ! id -u "$LATENCY_PROBE_USER" >/dev/null 2>&1; then
  echo "Creating user $LATENCY_PROBE_USER"
  useradd --system --create-home --shell /usr/sbin/nologin "$LATENCY_PROBE_USER"
fi

# Create install directory
mkdir -p "$LATENCY_PROBE_INSTALL_DIR"
chown -R "$LATENCY_PROBE_USER:$LATENCY_PROBE_GROUP" "$LATENCY_PROBE_INSTALL_DIR"
chmod 750 "$LATENCY_PROBE_INSTALL_DIR"

# Check latency-probe binary not exists
if [ ! -z "$LATENCY_PROBE_BIN_PATH" ]; then
  echo "Downloading binary $LATENCY_PROBE_VERSION into $LATENCY_PROBE_INSTALL_DIR"
  rm -rf "$LATENCY_PROBE_INSTALL_DIR"/*
  wget -O $LATENCY_PROBE_INSTALL_DIR/latency-probe.tar.gz ${LATENCY_PROBE_GIT_REPO}/releases/download/${LATENCY_PROBE_VERSION}/latency-probe-${LATENCY_PROBE_VERSION}.linux-amd64.tar.gz
  tar -xzf $LATENCY_PROBE_INSTALL_DIR/latency-probe.tar.gz -C $LATENCY_PROBE_INSTALL_DIR
  chmod +x $LATENCY_PROBE_INSTALL_DIR/latency-probe
  mv $LATENCY_PROBE_INSTALL_DIR/latency-probe $LATENCY_PROBE_BIN_PATH
fi

# Set capabilities so binary can use raw sockets (ICMP). This avoids running as root.
# cap_net_raw for raw socket, cap_net_admin for timestamping / NIC features
if command -v setcap >/dev/null 2>&1; then
  echo "Setting capabilities CAP_NET_RAW,CAP_NET_ADMIN on $LATENCY_PROBE_BIN_PATH"
  setcap 'cap_net_raw,cap_net_admin+ep' "$LATENCY_PROBE_BIN_PATH" || true
else
  echo "setcap not found; attempting to install libcap2-bin or libcap"
  case "$OS" in
    ubuntu|debian)
      apt-get install -y libcap2-bin
      setcap 'cap_net_raw,cap_net_admin+ep' "$LATENCY_PROBE_BIN_PATH" || true
      ;;
    amzn|amzn2|centos)
      yum install -y libcap
      setcap 'cap_net_raw,cap_net_admin+ep' "$LATENCY_PROBE_BIN_PATH" || true
      ;;
  esac
fi

# Create configuration directory and a default config file
LATENCY_PROBE_CFG_DIR="/etc/latency-probe"
mkdir -p "$LATENCY_PROBE_CFG_DIR"
cat > "$LATENCY_PROBE_CFG_DIR/config.json" <<'EOF'
{
  "probe_interval_ms": 3000,
  "default_timeout_ms": 2000,
  "log_level": "error",
  "enable_latency_history": false,
  "targets": __TARGETS_PLACEHOLDER__
}
EOF
chown -R root:root "$LATENCY_PROBE_CFG_DIR"
chmod 0755 "$LATENCY_PROBE_CFG_DIR"
chmod 0644 "$LATENCY_PROBE_CFG_DIR/config.json"

# Create environment file for systemd to inherit AppConfig identifiers and poll interval
LATENCY_PROBE_ENV_FILE="${LATENCY_PROBE_CFG_DIR}/env"
cat > "$LATENCY_PROBE_ENV_FILE" <<EOF
# Environment variables for latency-probe service
APP_CONFIG_APPLICATION_ID=${LATENCY_PROBE_APP_ID}
APP_CONFIG_ENVIRONMENT_ID=${LATENCY_PROBE_ENV_ID}
APP_CONFIG_PROFILE_ID=${LATENCY_PROBE_PROFILE_ID}
AWS_REGION=${LATENCY_PROBE_AWS_REGION}
APP_CONFIG_POLL_INTERVAL_SECONDS=${LATENCY_PROBE_APP_CONFIG_POLL_INTERVAL_SECONDS}
# Additional flags: e.g. --config path or extra flags
TARGET_CONFIG=${LATENCY_PROBE_CFG_DIR}/config.json
EOF
chmod 0644 "$LATENCY_PROBE_ENV_FILE"

# Create systemd service
LATENCY_PROBE_SYSTEMD_UNIT="/etc/systemd/system/${LATENCY_PROBE_SERVICE_NAME}"
cat > "$LATENCY_PROBE_SYSTEMD_UNIT" <<EOF
[Unit]
Description=Latency Probe (Rust)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${LATENCY_PROBE_ENV_FILE}
User=${LATENCY_PROBE_USER}
Group=${LATENCY_PROBE_GROUP}
# Limit file descriptors higher for heavy probing
LimitNOFILE=65536
# Give the binary capability to use raw sockets; keep the process non-root.
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
PrivateTmp=true
NoNewPrivileges=true
# Use taskset to pin to CPU(s) to reduce scheduling jitter - adjust PROBE_CPU_LIST as needed
ExecStart=/bin/sh -c "exec taskset -c 0-$(($(nproc) - 1)) ${LATENCY_PROBE_BIN_PATH}"
Restart=on-failure
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and start service
echo "Reloading systemd and enabling service..."
systemctl daemon-reload
systemctl enable --now "${LATENCY_PROBE_SERVICE_NAME}"

# Grant kernel settings that might help timing jitter (optional)
# Adjust kernel scheduler and CPU frequency scaling to reduce jitter:
echo "Applying optional kernel tuning to reduce timer jitter (best-effort)."
# 1) Prefer performance governor if available
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
  if command -v cpupower >/dev/null 2>&1; then
    cpupower frequency-set -g performance || true
  elif command -v cpufreq-set >/dev/null 2>&1; then
    cpufreq-set -r -g performance || true
  fi
fi

# Clean up
rm -rf $LATENCY_PROBE_INSTALL_DIR

# 2) Disable C-states (can reduce power savings, improves latency) - best to configure via kernel args or vendor tools.
# This is only a hint and left commented by default:
# echo "disabling deep C-states might improve jitter; consider setting intel_idle.max_cstate=0 on kernel cmdline."

# 3) Increase timer frequency? Not recommended to change without testing.

# Print instructions to user
echo ""
echo "=== Setup complete ==="
echo "Service: ${LATENCY_PROBE_SERVICE_NAME}"
echo "Binary: ${LATENCY_PROBE_BIN_PATH}"
echo "Config: ${LATENCY_PROBE_CFG_DIR}/config.json"
echo "Env file: ${LATENCY_PROBE_ENV_FILE}"
echo ""
echo "Check service status: sudo systemctl status ${LATENCY_PROBE_SERVICE_NAME}"
echo "View logs: sudo journalctl -u ${LATENCY_PROBE_SERVICE_NAME} -f"
echo ""
echo "If you need the probe binary to run with elevated realtime scheduling,"
echo "you may grant CAP_SYS_NICE or configure systemd to use SCHED_FIFO (use with caution)."
echo ""
echo "Notes:"
echo "- Ensure your instance has an IAM role that allows any AWS AppConfig retrieval (if you use AppConfig SDK with retrieval role)."
echo "- The Rust probe app must read APP_CONFIG_* env vars and poll AppConfig Data API every ${LATENCY_PROBE_APP_CONFIG_POLL_INTERVAL_SECONDS}s."
echo "- If you want to run in Docker instead of systemd, modify ExecStart accordingly."

