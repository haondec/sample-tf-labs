# Create VPC
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.project_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = false

  tags = merge(var.global_tags, {
    Environment = var.environment
    Name = "${var.project_prefix}-vpc"
  })
}

# Create SSH key
resource "aws_key_pair" "sample" {
  count = var.public_key != null && var.public_key.enable ? 1 : 0
  key_name   = var.public_key.name
  public_key = file(var.public_key.path)
}

# Fetch Ubuntu 24.04 AMI
data "aws_ami" "ubuntu_24_04" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  owners = var.ami.owners
}

# output "ubuntu_24_04_ami_id" {
#   value = data.aws_ami.ubuntu_24_04.id
# }

# Render config for probe host
locals {
  targets_json = jsonencode([
    {
      name = module.ec2_instance_target_host.private_ip
      kind = "icmp"
      host = module.ec2_instance_target_host.private_ip
    }
  ])
  
  user_data_script = replace(
    file("${path.module}/data/setup-probe-host.sh"),
    "__TARGETS_PLACEHOLDER__",
    local.targets_json
  )
}

# Setup probe host
module "ec2_instance_probe_host" {
  source  = "terraform-aws-modules/ec2-instance/aws"

  name = "${var.project_prefix}-probe-host"

  instance_type = "t3.micro"
  key_name      = var.public_key != null && var.public_key.enable ? var.public_key.name : null
  monitoring    = true
  subnet_id     = module.vpc.private_subnets[0]
  ami           = data.aws_ami.ubuntu_24_04.id

  create_security_group = true
  security_group_ingress_rules = {
    allow_ssh_ipv4 = {
      description = "Allow ssh VPC"
      from_port = 22
      to_port = 22
      ip_protocol = "tcp"
      cidr_ipv4 = module.vpc.vpc_cidr_block
    },
    allow_probe_port_ipv4 = {
      description = "Probe host port"
      from_port = 9100
      to_port = 9100
      ip_protocol = "tcp"
      cidr_ipv4 = "0.0.0.0/0"
    }
  }

  # User data with templated target configuration
  user_data = local.user_data_script

  tags = merge(var.global_tags, {
    Environment = var.environment
    Name = "${var.project_prefix}-probe-host"
  })
}

# Set up target host
module "ec2_instance_target_host" {
  source  = "terraform-aws-modules/ec2-instance/aws"

  name = "${var.project_prefix}-target-host"

  instance_type = "t3.micro"
  key_name      = var.public_key != null && var.public_key.enable ? var.public_key.name : null
  monitoring    = true
  subnet_id     = module.vpc.private_subnets[0]
  ami           = data.aws_ami.ubuntu_24_04.id

  security_group_ingress_rules = {
    # Allow icmp
    allow_icmp_ipv4 = {
      description = "Allow icmp"
      from_port = -1 # All icmp types
      to_port = -1
      ip_protocol = "icmp"
      cidr_ipv4 = "0.0.0.0/0"
    }
  }

  tags = merge(var.global_tags, {
    Environment = var.environment
    Name = "${var.project_prefix}-target-host"
  })
}