# modules/route53_failover/main.tf

# Create the health check for the primary ALB
resource "aws_route53_health_check" "primary" {
  fqdn             = var.primary_alb_dns
  port             = 80   # or 443 for HTTPS
  type             = "HTTP"
  resource_path    = "/"
  failure_threshold = 3
}

# Create the health check for the secondary ALB
resource "aws_route53_health_check" "secondary" {
  fqdn             = var.secondary_alb_dns
  port             = 80
  type             = "HTTP"
  resource_path    = "/"
  failure_threshold = 3
}

# A record for the primary ALB with failover routing
resource "aws_route53_record" "primary_a_record" {
  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "A"

  alias {
    name                   = var.primary_alb_dns
    zone_id                = data.aws_lb.primary_alb.zone_id   # ALB's zone ID
    evaluate_target_health = true
  }

  set_identifier = "primary"
  failover       = "PRIMARY"

  health_check_id = aws_route53_health_check.primary.id
}

# A record for the secondary ALB with failover routing
resource "aws_route53_record" "secondary_a_record" {
  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "A"

  alias {
    name                   = var.secondary_alb_dns
    zone_id                = data.aws_lb.secondary_alb.zone_id  # ALB's zone ID
    evaluate_target_health = true
  }

  set_identifier = "secondary"
  failover       = "SECONDARY"

  health_check_id = aws_route53_health_check.secondary.id
}

# Fetch ALB's zone ID for the primary ALB
data "aws_lb" "primary_alb" {
  name   = var.primary_alb_name
  region = var.region
}

# Fetch ALB's zone ID for the secondary ALB
data "aws_lb" "secondary_alb" {
  name   = var.secondary_alb_name
  region = var.region
}
