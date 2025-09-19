# provider "aws" {
#   access_key                  = "test"
#   secret_key                  = "test"
#   region                      = "us-east-1"

#   # Point to LocalStack running on Host A
#   endpoints {
#     s3 = "http://local-ubuntu-master:4566"
#     ec2 = "http://local-ubuntu-master:4566"
#     dynamodb = "http://local-ubuntu-master:4566"
#   }

#   # Disable account ID checks
#   skip_credentials_validation = true
#   skip_metadata_api_check     = true
#   skip_requesting_account_id  = true
# }

terraform {
  backend "s3" {
    bucket = "your-bucket-name"
    key    = "projects/sample/sample-default.tfstate"
    region = "your-region"
  }

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">=3.4.3"
    }

    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.59.0"
    }
  }

  required_version = ">= 1.4.2"
}

provider "aws" {
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::your-account-id:role/your-role-name"
  }
}

data "aws_caller_identity" "current" {}