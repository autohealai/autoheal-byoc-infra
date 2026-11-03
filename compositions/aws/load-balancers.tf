# The edge Network Load Balancer, created in this apply when edge_mode is
# loadbalancer so its address is known before the chart is installed. The chart
# binds the proxy Service to its target groups with TargetGroupBinding resources
# (global.infra.targetGroups), and the AWS Load Balancer Controller registers
# the pod IPs. The load balancer has a security group; the node security group
# gets ingress from it on the target ports only.
#
# 443 goes to the proxy's 8443 (TLS ends at the proxy) and 80 to its redirect
# listener on 8090. The load balancer is internal in the private subnets, or
# internet-facing in the public subnets (edge_exposure). Clients connect from
# edge_allowed_cidr_blocks, default the VPC CIDR.
#
# With existing_edge_security_group_id the load balancer uses that group and we
# add no security group rule, on it or on the nodes' group. The
# required_edge_owner_actions output lists the rules its owner adds.
#
# edge_lb_tags go on the load balancer alone, on top of tags, and are set when
# it is created: the moment an account's automation (DNS records, for example)
# looks at a new load balancer. Added later, they only tag the existing one.

module "edge_nlb" {
  source = "../../modules/aws/nlb"
  count  = local.create_edge_lb ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["edge"]
  tags        = var.tags

  vpc_id         = local.vpc_id
  vpc_cidr_block = local.vpc_cidr_block
  subnet_ids     = var.edge_exposure == "internal" ? local.private_subnet_ids : local.public_subnet_ids
  internal       = var.edge_exposure == "internal"

  listeners = {
    https = {
      port        = 443
      target_port = 8443
    }
    http = {
      port        = 80
      target_port = 8090
    }
  }

  existing_security_group_id = var.existing_edge_security_group_id
  allowed_cidr_blocks        = local.edge_allowed_cidr_blocks
  target_security_group_ids  = local.edge_sg_brought ? [] : [local.node_security_group_id]

  lb_tags = var.edge_lb_tags
}

locals {
  edge_allowed_cidr_blocks = length(var.edge_allowed_cidr_blocks) > 0 ? var.edge_allowed_cidr_blocks : [local.vpc_cidr_block]
  edge_sg_brought          = local.create_edge_lb && var.existing_edge_security_group_id != ""

  # Listed in the required_edge_owner_actions output: the rules we would have
  # made, for the owner of a brought edge security group.
  edge_owner_actions = local.edge_sg_brought ? [
    "Ingress rules on security group ${var.existing_edge_security_group_id} allowing TCP 443 and 80 from ${join(", ", local.edge_allowed_cidr_blocks)}: the clients of the edge load balancer",
    "Egress rules on security group ${var.existing_edge_security_group_id} allowing TCP ${join(" and ", local.lb_target_ports)} to ${local.vpc_cidr_block}: the load balancer sends traffic and health checks to the proxy pods",
    "Ingress rules on security group ${local.node_security_group_id}, the security group the cluster's pods run with, allowing TCP ${join(" and ", local.lb_target_ports)} from ${var.existing_edge_security_group_id}",
  ] : []

  # Target group ARNs the chart binds to, keyed by the chart's names. Empty
  # unless edge_mode is loadbalancer.
  target_group_arns = { for k, v in {
    edgeHttps = one(module.edge_nlb[*].target_group_arns["https"])
    edgeHttp  = one(module.edge_nlb[*].target_group_arns["http"])
  } : k => v if local.create_edge_lb }
}
