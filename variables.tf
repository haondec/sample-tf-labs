variable "global_tags" {
  type = map(string)
  default = {
    Terraform = "true"
  }
}

variable "environment" {
  type = string
  default = "dev"
}

variable "project_prefix" {
  type = string
  default = "sample"
}

variable "region" {
  type = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type = string
  default = "10.0.0.0/20"
}

variable "azs" {
  type = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_key" {
  type = object({
    enable = bool
    name = string
    path = string
  })
  default = {
    enable = true
    name = "sample"
    path = "./data/ssh/sample.pub"
  }
}

variable "ami" {
  type = object({
    name = string
    owners = list(string)
  })
  default = {
    name = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20250627"
    owners = ["099720109477"] # Canonical
  }
}