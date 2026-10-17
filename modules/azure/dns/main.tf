# A records in a DNS zone the customer already has. The AWS analogue is
# modules/aws/dns (Route 53). This module never creates the zone: the composition
# passes the zone name and resource group parsed from existing_dns_zone_id.
#
# The zone may be public (Microsoft.Network/dnszones) or private
# (Microsoft.Network/privateDnsZones); private_zone picks the resource type.
#
# records maps a name relative to the zone ("@" for the apex, "auth" for
# auth.<zone>) to the IPv4 address it points at. Keys must be known at plan time;
# values may be computed.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

resource "azurerm_dns_a_record" "this" {
  for_each            = var.private_zone ? {} : var.records
  name                = each.key
  zone_name           = var.zone_name
  resource_group_name = var.zone_resource_group_name
  ttl                 = var.ttl
  records             = [each.value]
  tags                = module.this.tags
}

resource "azurerm_private_dns_a_record" "this" {
  for_each            = var.private_zone ? var.records : {}
  name                = each.key
  zone_name           = var.zone_name
  resource_group_name = var.zone_resource_group_name
  ttl                 = var.ttl
  records             = [each.value]
  tags                = module.this.tags
}
