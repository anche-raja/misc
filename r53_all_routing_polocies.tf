# main.tf
resource "aws_route53_record" "this" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = var.is_alias ? "A" : var.record_type

  # Alias record configuration
  dynamic "alias" {
    for_each = var.is_alias ? [1] : []
    content {
      name                   = var.alias_target.name
      zone_id                = var.alias_target.zone_id
      evaluate_target_health = true
    }
  }

  # Non-alias record configuration
  ttl     = var.is_alias ? null : var.ttl
  records = var.is_alias ? null : var.records

  # Routing policies (only applicable for non-alias records)
  dynamic "weighted_routing_policy" {
    for_each = var.routing_policy == "weighted" && !var.is_alias ? [1] : []
    content {
      weight = var.weight
    }
  }

  dynamic "latency_routing_policy" {
    for_each = var.routing_policy == "latency" && !var.is_alias ? [1] : []
    content {
      region = var.region
    }
  }

  dynamic "failover_routing_policy" {
    for_each = var.routing_policy == "failover" && !var.is_alias ? [1] : []
    content {
      type = var.failover
    }
  }

  dynamic "geolocation_routing_policy" {
    for_each = var.routing_policy == "geolocation" && !var.is_alias ? [1] : []
    content {
      continent_code   = var.geo_location.continent_code
      country_code     = var.geo_location.country_code
      subdivision_code = var.geo_location.subdivision_code
    }
  }

  multivalue_answer_routing_policy = var.routing_policy == "multivalue" && !var.is_alias ? true : false
}
