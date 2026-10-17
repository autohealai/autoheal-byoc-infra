# DNS records for the three hostnames in the customer's existing zone (public or
# private), read from existing_dns_zone_id. We never create the zone.
#
# The records point at the reserved proxy address in loadbalancer mode, so DNS is
# right from this apply, before the chart is installed. In the other modes they
# point at edge_address. When we do not create them (create_dns_records = false,
# or no edge_address yet) the required_dns_records output lists them instead.

module "dns" {
  source = "../../modules/azure/dns"
  count  = local.dns_records_created ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["dns"]
  tags        = var.tags

  zone_name                = local.dns_zone_name
  zone_resource_group_name = local.dns_zone_rg
  private_zone             = local.dns_zone_private
  ttl                      = var.dns_record_ttl

  records = { for k, h in local.hosts : local.dns_record_names[k] => local.dns_target }
}

locals {
  # The records for a person to create. The value is the address the records must
  # point at, or a placeholder when it is not known yet (an edge mode other than
  # loadbalancer with no edge_address).
  required_dns_records = local.dns_records_created ? [] : [
    for k in ["app", "auth", "authApp"] : {
      name  = local.hosts[k]
      type  = "A"
      value = local.dns_target != "" ? local.dns_target : "<address of your gateway or ingress>"
    }
  ]
}
