# resource "aws_s3_bucket" "probe_configs" {
#   bucket = "${var.project_prefix}-probe-configs"
# }

# resource "aws_s3_object" "targets" {
#   bucket = aws_s3_bucket.probe_configs.bucket
#   key    = "targets.json"
#   content = <<EOT
# {
#   "targets": [
#     { "name": "target-host", "host": "${module.ec2_instance_target_host.private_ip}", "protocol": "icmp" }
#   ],
#   "probe_interval_ms": 1000
# }
# EOT
#   depends_on = [
#     aws_s3_bucket.probe_configs,
#     module.ec2_instance_probe_host,
#     module.ec2_instance_target_host
#   ]
# }

# resource "aws_iam_role" "appconfig_retrieval" {
#   name = "${var.project_prefix}-appconfig-retrieval"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = {
#         Service = "appconfig.amazonaws.com"
#       }
#     }]
#   })
# }

# resource "aws_iam_role_policy" "appconfig_retrieval" {
#   name = "${var.project_prefix}-appconfig-retrieval"
#   role = aws_iam_role.appconfig_retrieval.id
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "s3:GetObject"
#       Effect = "Allow"
#       Resource = "arn:aws:s3:::${aws_s3_bucket.probe_configs.bucket}/targets.json"
#     }]
#   })
# }

# resource "aws_appconfig_application" "probe_app" {
#   name        = "latency-probe"
#   description = "AppConfig for probe targets"
# }

# resource "aws_appconfig_environment" "dev" {
#   application_id = aws_appconfig_application.probe_app.id
#   name           = "dev"
# }

# resource "aws_appconfig_configuration_profile" "targets_profile" {
#   application_id = aws_appconfig_application.probe_app.id
#   name           = "targets"
#   location_uri   = "arn:aws:s3:::${aws_s3_bucket.probe_configs.bucket}/targets.json"
#   retrieval_role_arn = aws_iam_role.appconfig_retrieval.arn
# }
