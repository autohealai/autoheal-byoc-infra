# DNS records for the three hostnames in the customer's Route 53 hosted zone
# (public or private), read from existing_dns_zone_id. We never create the zone.
#
# In loadbalancer mode the records are aliases to the edge load balancer, so DNS
# is right from this apply, before the chart is installed. In the other modes
# they point at edge_address: A records for an IPv4 address, CNAME records for a
# DNS name. When we do not create them (create_dns_records = false, or no
# edge_address yet) the required_dns_records output lists them instead.

data "aws_route53_zone" "this" {
  count   = var.existing_dns_zone_id != "" ? 1 : 0
  zone_id = var.existing_dns_zone_id
}

locals {
  edge_address_is_ip = var.edge_address != "" && can(cidrhost("${var.edge_address}/32", 0))

  dns_records = {
    for k, h in local.hosts : k => {
      name    = h
      type    = local.create_edge_lb || local.edge_address_is_ip ? "A" : "CNAME"
      ttl     = var.dns_record_ttl
      records = local.create_edge_lb ? [] : [var.edge_address]
      alias = local.create_edge_lb ? {
        name                   = one(module.edge_nlb[*].dns_name)
        zone_id                = one(module.edge_nlb[*].zone_id)
        evaluate_target_health = true
      } : null
    }
  }

  # The records for a person to create, when we do not create them (none in
  # edge_mode = none, where the customer routes traffic themselves). In
  # loadbalancer mode a CNAME to the load balancer's DNS name works in any DNS
  # service (an alias needs Route 53); at a zone apex use your provider's alias
  # or ALIAS record instead.
  required_dns_records = local.dns_records_created || var.edge_mode == "none" ? [] : [
    for k in ["app", "auth", "authApp"] : {
      name = local.hosts[k]
      type = local.create_edge_lb ? "CNAME" : (var.edge_address == "" ? "A or CNAME" : local.dns_records[k].type)
      value = (
        local.create_edge_lb ? one(module.edge_nlb[*].dns_name) :
        var.edge_address != "" ? var.edge_address : "<address of your gateway or ingress>"
      )
    }
  ]
}

module "dns" {
  source = "../../modules/aws/route53"
  count  = local.dns_records_created ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["dns"]
  tags        = var.tags

  zone_id = var.existing_dns_zone_id
  records = local.dns_records
}
