# variables.tf
variable "tf_region" {
  description = "Specify the region to deploy (east, west, or both)"
  type        = string
}

variable "primary_region" {
  description = "The primary AWS region (east)"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "The secondary AWS region (west)"
  type        = string
  default     = "us-west-2"
}


# main.tf
locals {
  regions = tomap(
    {
      "east" = var.primary_region
      "west" = var.secondary_region
    }
  )

  selected_regions = (
    var.tf_region == "east" ? { "primary" = local.regions["east"] } :
    var.tf_region == "west" ? { "secondary" = local.regions["west"] } :
    var.tf_region == "both" ? local.regions : {}
  )
}


# Using for_each to create resources in the selected regions
resource "aws_security_group" "example" {
  for_each = local.selected_regions

  provider = aws.region {
    alias  = each.key
    region = each.value
  }

  name   = "example-sg-${each.key}"
  vpc_id = "vpc-12345678"
}

resource "aws_vpc_endpoint" "example" {
  for_each = local.selected_regions

  provider = aws.region {
    alias  = each.key
    region = each.value
  }

  vpc_id            = "vpc-12345678"
  service_name      = "com.amazonaws.${each.value}.s3"
  vpc_endpoint_type = "Gateway"
}


provider "aws" {
  alias  = "primary"
  region = var.primary_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}
