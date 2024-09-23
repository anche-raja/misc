# main.tf
module "vpc_hosted_zone_association" {
  source = "./modules/hosted_zone_association"
  
  domain_name = "example.com"
}

# Fetch the VPCs in both regions (us-east-1 and us-west-2)
data "aws_vpc" "east_vpc" {
  filter {
    name   = "tag:Name"
    values = ["east-vpc-name"]  # Replace with the VPC name or other identifier
  }
  region = "us-east-1"
}

data "aws_vpc" "west_vpc" {
  filter {
    name   = "tag:Name"
    values = ["west-vpc-name"]  # Replace with the VPC name or other identifier
  }
  region = "us-west-2"
}

# Pass the dynamically fetched VPC IDs to the module
module "vpc_hosted_zone_association" {
  source      = "./modules/hosted_zone_association"
  domain_name = "example.com"
  vpc_ids     = [data.aws_vpc.east_vpc.id, data.aws_vpc.west_vpc.id]
  vpc_regions = ["us-east-1", "us-west-2"]
}

# modules/hosted_zone_association/main.tf
variable "domain_name" {
  description = "The domain name for the Route53 hosted zone."
  type        = string
}

variable "vpc_ids" {
  description = "List of VPC IDs to associate with the Route53 hosted zone."
  type        = list(string)
}

variable "vpc_regions" {
  description = "List of regions corresponding to the VPCs."
  type        = list(string)
}

# Create a private hosted zone
resource "aws_route53_zone" "private_zone" {
  name = var.domain_name
  vpc {
    vpc_id     = var.vpc_ids[0]  # Associate with first VPC during creation
    vpc_region = var.vpc_regions[0]
  }
  comment     = "Private Hosted Zone for ${var.domain_name}"
  private_zone = true
}

# Associate additional VPCs
resource "aws_route53_zone_association" "vpc_association" {
  count      = length(var.vpc_ids)
  zone_id    = aws_route53_zone.private_zone.zone_id
  vpc_id     = var.vpc_ids[count.index]
  vpc_region = var.vpc_regions[count.index]
}
