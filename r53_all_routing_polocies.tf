# main.tf
resource "aws_route53_record" "this" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = var.record_type
  ttl     = var.ttl

  # For CNAME records, Route 53 expects only one value in records
  records = var.record_type == "CNAME" ? [var.records[0]] : var.records

  # Weighted routing policy
  dynamic "weighted_routing_policy" {
    for_each = var.routing_policy == "weighted" ? [1] : []
    content {
      weight = var.weight
    }
  }

  # Latency-based routing
  dynamic "latency_routing_policy" {
    for_each = var.routing_policy == "latency" ? [1] : []
    content {
      region = var.region
    }
  }

  # Failover routing policy
  dynamic "failover_routing_policy" {
    for_each = var.routing_policy == "failover" ? [1] : []
    content {
      type = var.failover
    }
  }

  # Geolocation routing policy
  dynamic "geolocation_routing_policy" {
    for_each = var.routing_policy == "geolocation" ? [1] : []
    content {
      continent_code   = var.geo_location.continent_code
      country_code     = var.geo_location.country_code
      subdivision_code = var.geo_location.subdivision_code
    }
  }

  # Multivalue answer routing policy
  multivalue_answer_routing_policy = var.routing_policy == "multivalue" ? true : false
}
