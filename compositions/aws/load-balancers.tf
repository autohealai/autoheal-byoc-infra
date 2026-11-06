# Network Load Balancers, created in this apply so their addresses are known
# before the chart is installed. The chart binds its Services to their target
# groups with TargetGroupBinding resources (global.infra.targetGroups), and the
# AWS Load Balancer Controller registers the pod IPs. Each load balancer has a
# security group; the node security group gets ingress from it on the target
# ports only.
#
#   edge    edge_mode = loadbalancer only. 443 goes to the proxy's 8443 (TLS
#           ends at the proxy) and 80 to its redirect listener on 8090.
#           Internal in the private subnets, or internet-facing in the public
#           subnets (edge_exposure). Clients connect from
#           edge_allowed_cidr_blocks, default the VPC CIDR.
#   runner  runner_lb_enabled only, for compositions/aws-runner. Internal, in
#           the private subnets: the Temporal frontend on 7233, and the
#           api-server-go internal listener on 8083, where the runner posts
#           sandbox tool results. This is how Autoheal's hosted runners reach
#           Temporal: plain gRPC and HTTP inside the network, with no TLS and
#           no key, so the security group alone decides who connects. Clients
#           connect from runner_lb_allowed_cidr_blocks and
#           runner_lb_allowed_security_group_ids, default the VPC CIDR.
#
# With existing_edge_security_group_id the edge load balancer uses that group
# and we add no security group rule for it, on it or on the nodes' group. The
# required_edge_owner_actions output lists the rules its owner adds.
# existing_runner_lb_security_group_id does the same for the runner load
# balancer, with required_runner_lb_owner_actions.
#
# edge_lb_tags go on the edge load balancer alone, on top of tags, and are set
# when it is created: the moment an account's automation (DNS records, for
# example) looks at a new load balancer. Added later, they only tag the
# existing one.

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

module "runner_nlb" {
  source = "../../modules/aws/nlb"
  count  = local.create_runner_lb ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["runner"]
  tags        = var.tags

  vpc_id         = local.vpc_id
  vpc_cidr_block = local.vpc_cidr_block
  subnet_ids     = local.private_subnet_ids
  internal       = true

  listeners = {
    temporal = {
      port = local.runner_lb_ports.temporal
    }
    tool-response = {
      port         = local.runner_lb_ports.tool_response
      health_check = { protocol = "HTTP", path = "/health" }
    }
  }

  existing_security_group_id = var.existing_runner_lb_security_group_id
  allowed_cidr_blocks        = local.runner_lb_allowed_cidr_blocks
  allowed_security_group_ids = var.runner_lb_allowed_security_group_ids
  target_security_group_ids  = local.runner_lb_sg_brought ? [] : [local.node_security_group_id]
}

# Infra 3.x created the runner load balancer without a count. An install that
# comes from 3.x with runner_lb_enabled keeps it and its target groups, so the
# runner address does not change.
moved {
  from = module.runner_nlb
  to   = module.runner_nlb[0]
}

locals {
  edge_allowed_cidr_blocks = length(var.edge_allowed_cidr_blocks) > 0 ? var.edge_allowed_cidr_blocks : [local.vpc_cidr_block]
  edge_sg_brought          = local.create_edge_lb && var.existing_edge_security_group_id != ""

  # Listed in the required_edge_owner_actions output: the rules we would have
  # made, for the owner of a brought edge security group.
  edge_owner_actions = local.edge_sg_brought ? [
    "Ingress rules on security group ${var.existing_edge_security_group_id} allowing TCP 443 and 80 from ${join(", ", local.edge_allowed_cidr_blocks)}: the clients of the edge load balancer",
    "Egress rules on security group ${var.existing_edge_security_group_id} allowing TCP ${join(" and ", local.edge_lb_target_ports)} to ${local.vpc_cidr_block}: the load balancer sends traffic and health checks to the proxy pods",
    "Ingress rules on security group ${local.node_security_group_id}, the security group the cluster's pods run with, allowing TCP ${join(" and ", local.edge_lb_target_ports)} from ${var.existing_edge_security_group_id}",
  ] : []

  # The ports of the runner load balancer, which are also the ports of the pods
  # behind it: the chart's Temporal frontend and api-server-go internal listener.
  runner_lb_ports = {
    temporal      = 7233
    tool_response = 8083
  }

  # Who may connect to the runner load balancer. With neither list set, the
  # VPC, as on Autoheal's hosted runners; a brought security group alone
  # narrows it to that group.
  runner_lb_allowed_cidr_blocks = (
    length(var.runner_lb_allowed_cidr_blocks) > 0 ? var.runner_lb_allowed_cidr_blocks :
    length(var.runner_lb_allowed_security_group_ids) > 0 ? [] : [local.vpc_cidr_block]
  )
  runner_lb_sg_brought = local.create_runner_lb && var.existing_runner_lb_security_group_id != ""

  # Listed in the required_runner_lb_owner_actions output: the rules we would
  # have made, for the owner of a brought runner security group.
  runner_lb_owner_actions = local.runner_lb_sg_brought ? [
    "Ingress rules on security group ${var.existing_runner_lb_security_group_id} allowing TCP ${join(" and ", values(local.runner_lb_ports))} from ${join(", ", concat(local.runner_lb_allowed_cidr_blocks, var.runner_lb_allowed_security_group_ids))}: the runner instances, which poll Temporal and post sandbox tool results",
    "Egress rules on security group ${var.existing_runner_lb_security_group_id} allowing TCP ${join(" and ", values(local.runner_lb_ports))} to ${local.vpc_cidr_block}: the load balancer sends traffic and health checks to the Temporal frontend and api-server-go pods",
    "Ingress rules on security group ${local.node_security_group_id}, the security group the cluster's pods run with, allowing TCP ${join(" and ", values(local.runner_lb_ports))} from ${var.existing_runner_lb_security_group_id}",
  ] : []

  # What compositions/aws-runner needs, from the runner_load_balancer output.
  runner_lb_dns_name = one(module.runner_nlb[*].dns_name)
  runner_lb = local.create_runner_lb ? {
    dns_name          = local.runner_lb_dns_name
    temporal_address  = "${local.runner_lb_dns_name}:${local.runner_lb_ports.temporal}"
    tool_response_url = "http://${local.runner_lb_dns_name}:${local.runner_lb_ports.tool_response}/api/v1/internal/sandbox-tool-responses"
    security_group_id = one(module.runner_nlb[*].security_group_id)
  } : null

  # Target group ARNs the chart binds to, keyed by the chart's names: edgeHttps
  # and edgeHttp in loadbalancer mode, temporal and toolResponse with the
  # runner load balancer.
  target_group_arns = merge(
    { for k, v in {
      edgeHttps = one(module.edge_nlb[*].target_group_arns["https"])
      edgeHttp  = one(module.edge_nlb[*].target_group_arns["http"])
    } : k => v if local.create_edge_lb },
    { for k, v in {
      temporal     = one(module.runner_nlb[*].target_group_arns["temporal"])
      toolResponse = one(module.runner_nlb[*].target_group_arns["tool-response"])
    } : k => v if local.create_runner_lb },
  )
}
