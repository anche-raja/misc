variable "hosted_zone_id" {
  description = "The ID of the hosted zone"
  type        = string
}

variable "domain_name" {
  description = "The domain name for the Route 53 record"
  type        = string
}

variable "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  type        = string
}

variable "record_type" {
  description = "The type of Route 53 record (A, CNAME, etc.)"
  type        = string
  default     = "A"
}

variable "routing_policy" {
  description = "The routing policy (simple, failover, weighted)"
  type        = string
}

variable "failover_type" {
  description = "Type of failover routing (PRIMARY or SECONDARY)"
  type        = string
  default     = null  # Should be provided if routing_policy is 'failover'
}

variable "health_check_id" {
  description = "Health check ID for failover routing"
  type        = string
  default     = null  # Should be provided if routing_policy is 'failover'
}

variable "ttl" {
  description = "TTL for the DNS record"
  type        = number
  default     = 300
}

variable "weight" {
  description = "Weight for weighted routing"
  type        = number
  default     = null  # Should be provided if routing_policy is 'weighted'
}

=============

resource "aws_route53_record" "this" {
  zone_id = var.hosted_zone_id
  name     = var.domain_name
  type     = var.record_type  # Use the record type provided

  # Create alias only for A or AAAA records
  dynamic "alias" {
    for_each = (var.record_type == "A" || var.record_type == "AAAA") ? [1] : []

    content {
      name                   = var.alb_dns_name
      zone_id                = aws_lb.my_alb.zone_id  # Adjust based on how you reference the ALB
      evaluate_target_health = true
    }
  }

  # Create failover routing policy if failover is selected
  dynamic "failover_routing_policy" {
    for_each = var.routing_policy == "failover" ? [1] : []  # Only create if failover routing is chosen

    content {
      type = var.failover_type  # PRIMARY or SECONDARY
    }
  }

  # Health check ID for failover routing
  dynamic "health_check_id" {
    for_each = var.routing_policy == "failover" ? [1] : []  # Only create if failover routing is chosen

    content {
      health_check_id = var.health_check_id  # Health check ID for failover
    }
  }

  # Create weighted routing policy if weighted is selected
  dynamic "weighted_routing_policy" {
    for_each = var.routing_policy == "weighted" ? [1] : []  # Only create if weighted routing is chosen

    content {
      weight = var.weight  # Weight for the weighted policy
    }
  }

  # TTL settings
  ttl = var.ttl
}




# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_role" {
  name = "alb-health-check-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for CloudWatch metrics and Route 53 access
resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData",
          "route53:GetHealthCheckStatus"
        ],
        Resource = "*"
      }
    ]
  })
}

# Lambda function to check ALB health and post metrics to CloudWatch
resource "aws_lambda_function" "alb_health_check" {
  function_name = var.lambda_function_name
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = var.lambda_s3_key
  handler       = "health_check.lambda_handler"
  runtime       = "python3.8"
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      ALB_DNS_NAME = var.alb_dns_name
    }
  }

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = var.lambda_security_group_ids
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.alb_health_check.function_name}"
  retention_in_days = 7
}

# CloudWatch Metric Alarm for the health check Lambda function
resource "aws_cloudwatch_metric_alarm" "alb_health_alarm" {
  alarm_name          = "${var.lambda_function_name}-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ALBHealthStatus"
  namespace           = "ALBHealth"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alarm if ALB health check fails"
}

# Route 53 Health Check linked to CloudWatch Alarm
resource "aws_route53_health_check" "alb_health_check" {
  type                            = "CLOUDWATCH_METRIC"
  alarm_identifier {
    region            = "us-west-1" # Modify based on your region
    name              = aws_cloudwatch_metric_alarm.alb_health_alarm.alarm_name
  }
  insufficient_data_health_status = "Unhealthy"
}

# Create Route 53 Record with Alias pointing to ALB and failover routing
resource "aws_route53_record" "failover_cname" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A" # Alias records must be type A or AAAA

  alias {
    name                   = var.alb_dns_name
    zone_id                = aws_lb.my_alb.zone_id # ALB Zone ID
    evaluate_target_health = true
  }

  set_identifier = var.failover_type # 'PRIMARY' or 'SECONDARY'
  failover_routing_policy {
    type = var.failover_type
  }

  health_check_id = aws_route53_health_check.alb_health_check.id
  ttl             = var.record_ttl
}
