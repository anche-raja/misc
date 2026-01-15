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

# Create the private hosted zone (initial creation, no VPC associations yet)
resource "aws_route53_zone" "private_zone" {
  name        = var.domain_name
  comment     = "Private Hosted Zone for ${var.domain_name}"
  private_zone = true
}

# Associate multiple VPCs with the hosted zone using a for_each loop
resource "aws_route53_zone_association" "vpc_association" {
  for_each   = tomap({ for idx, vpc_id in var.vpc_ids : idx => {
    vpc_id     = vpc_id
    vpc_region = var.vpc_regions[idx]
  }})

  zone_id    = aws_route53_zone.private_zone.zone_id
  vpc_id     = each.value.vpc_id
  vpc_region = each.value.vpc_region

  lifecycle {
    ignore_changes = [vpc_id]
  }
}
