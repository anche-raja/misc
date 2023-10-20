#########################################################################
# Basic Required Config for Terraform And AWS
#########################################################################
terraform {
  required_version = ">=1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=5.0.0"
    }
  }
  backend "s3" {
    bucket = "q3-cc-app-remote-state"
    key    = "terraform_state/terraform.tfstate"
    region = "us-east-1"
  }
}
provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Environment = var.environment
      Organization = var.org
      Application = var.project
    }
  }
}
