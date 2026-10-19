# DNS records in a Route 53 hosted zone the customer already has, public or
# private. The Azure analogue is modules/azure/dns. This module never creates
# the zone: the composition passes its ID.
#
# Each record is an A record with addresses, an A alias (for a load balancer),
# or a CNAME. records is keyed by a stable key chosen by the caller, so keys are
# known at plan; the values (alias targets, addresses) may be computed in the
# same apply.
#
# Route 53 records take no tags, so module.this is only declared for the
# shared label inputs. See label.tf.

resource "aws_route53_record" "this" {
  for_each = var.records

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.alias == null ? each.value.ttl : null
  records = each.value.alias == null ? each.value.records : null

  dynamic "alias" {
    for_each = each.value.alias == null ? [] : [each.value.alias]
    content {
      name                   = alias.value.name
      zone_id                = alias.value.zone_id
      evaluate_target_health = alias.value.evaluate_target_health
    }
  }
}
