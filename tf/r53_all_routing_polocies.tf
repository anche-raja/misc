# variables.tf
variable "zone_id" {
  description = "The ID of the Route 53 hosted zone"
  type        = string
}

variable "record_name" {
  description = "The name of the DNS record (domain or subdomain)"
  type        = string
}

variable "record_type" {
  description = "The DNS record type (A or CNAME)"
  type        = string
}

variable "is_alias" {
  description = "Boolean to indicate if the record is an alias"
  type        = bool
  default     = false
}

variable "alias_target" {
  description = "The alias target (for alias records)"
  type = object({
    name    = string
    zone_id = string
  })
  default = null
}

variable "ttl" {
  description = "Time to live for the DNS record"
  type        = number
  default     = 300
}

variable "routing_policy" {
  description = "The routing policy for the record (simple, weighted, failover)"
  type        = string
  default     = "simple"
}

variable "failover_type" {
  description = "Failover type (PRIMARY or SECONDARY), used for failover routing"
  type        = string
  default     = null
}

variable "weight" {
  description = "Weight for weighted routing, only required for weighted routing"
  type        = number
  default     = null
}

variable "set_identifier" {
  description = "Unique identifier for the record, used for weighted and failover routing"
  type        = string
  default     = null
}


# main.tf
resource "aws_route53_record" "dns_record" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = var.is_alias ? "A" : var.record_type

  # Alias configuration (for ALB or other AWS resources)
  dynamic "alias" {
    for_each = var.is_alias ? [1] : []
    content {
      name                   = var.alias_target.name
      zone_id                = var.alias_target.zone_id
      evaluate_target_health = true
    }
  }

  # Non-alias records (A, CNAME, etc.)
  ttl     = var.is_alias ? null : var.ttl
  records = var.is_alias ? null : []

  # Failover routing policy
  dynamic "failover_routing_policy" {
    for_each = var.routing_policy == "failover" ? [1] : []
    content {
      type = var.failover_type
    }
  }

  # Weighted routing policy
  dynamic "weighted_routing_policy" {
    for_each = var.routing_policy == "weighted" ? [1] : []
    content {
      weight = var.weight
    }
  }

  # Set identifier for both failover and weighted routing
  set_identifier = var.set_identifier
}
