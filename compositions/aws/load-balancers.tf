# Network Load Balancers, created in this apply so their addresses are known
# before the chart is installed. The chart binds its Services to their target
# groups with TargetGroupBinding resources (global.infra.targetGroups), and the
# AWS Load Balancer Controller registers the pod IPs. Each load balancer has a
# security group; the node security group gets ingress from it on the target
# ports only.
#
#   runner  internal, private subnets. Temporal frontend on 7233 and the
#           api-server-go internal listener on 8083 (sandbox tool results).
#           Only the runner VMs may connect.
#   edge    edge_mode = loadbalancer only. 443 to the proxy's 8443 (TLS ends
#           at the proxy) and 80 to its redirect listener on 8090. internal in
#           the private subnets, or internet-facing in the public subnets
#           (edge_exposure). Clients from edge_allowed_cidr_blocks, default the
#           VPC CIDR.

module "runner_nlb" {
  source = "../../modules/aws/nlb"

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
      port = 7233
    }
    tool-response = {
      port         = 8083
      health_check = { protocol = "HTTP", path = "/health" }
    }
  }

  allowed_security_group_ids = [module.runner.security_group_id]
  target_security_group_ids  = [local.node_security_group_id]
}

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
  # Target group ARNs the chart binds to, keyed by the chart's names.
  target_group_arns = merge(
    {
      temporal     = module.runner_nlb.target_group_arns["temporal"]
      toolResponse = module.runner_nlb.target_group_arns["tool-response"]
    },
    { for k, v in {
      edgeHttps = one(module.edge_nlb[*].target_group_arns["https"])
      edgeHttp  = one(module.edge_nlb[*].target_group_arns["http"])
    } : k => v if local.create_edge_lb },
  )

  runner_nlb_dns_name = module.runner_nlb.dns_name
}
