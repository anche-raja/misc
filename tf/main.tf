# #########################################################################
# # Basic Required Config for Terraform And AWS
# #########################################################################
# terraform {
#   required_version = ">=1.0.0"
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = ">=5.0.0"
#     }
#   }
#   backend "s3" {
#     bucket = "your-bucket-name-here"
#     key    = "terraform_state/terraform.tfstate"
#     region = "us-east-1"
#   }
# }
# provider "aws" {
#   region = "us-east-1"
# }



# first init plan apply cycle 
# Comment after creating backend S3 bucket.
provider "aws" {
  version = ">=1.0.0"
  region  = "us-east-1"
}

resource "aws_s3_bucket" "terraform_remote_state" {
  bucket = "q3-cc-app-remote-state"
  acl    = "private"

  tags = {
    Name        = "terraform-remote-state"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket" "db_terraform_remote_state" {
  bucket = "q3-cc-db-remote-state"
  acl    = "private"

  tags = {
    Name        = "terraform-remote-state"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket" "raja_terraform_remote_state" {
  bucket = "q3-cc-raja-remote-state"
  acl    = "private"

  tags = {
    Name        = "terraform-remote-state"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket" "petclinic_terraform_remote_state" {
  bucket = "petclinic-remote-state"
  acl    = "private"

  tags = {
    Name        = "terraform-remote-state"
    Environment = "Dev"
  }
}

