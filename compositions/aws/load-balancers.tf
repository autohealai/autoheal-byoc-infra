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

  allowed_cidr_blocks       = length(var.edge_allowed_cidr_blocks) > 0 ? var.edge_allowed_cidr_blocks : [local.vpc_cidr_block]
  target_security_group_ids = [local.node_security_group_id]
}

locals {
  # Target group ARNs the chart binds to, keyed by the chart's names. Empty
  # unless edge_mode is loadbalancer.
  target_group_arns = { for k, v in {
    edgeHttps = one(module.edge_nlb[*].target_group_arns["https"])
    edgeHttp  = one(module.edge_nlb[*].target_group_arns["http"])
  } : k => v if local.create_edge_lb }
}
