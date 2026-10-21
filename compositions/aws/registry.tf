# Image registry: an ECR pull-through cache of the public Autoheal registry
# (create_registry), the customer's mirror (existing_registry_url), or none.
#
# With the pull-through cache, the first pull of an image copies it from
# public.ecr.aws/e4h3h0d9 into a private repository under registry_repository_prefix;
# later pulls are served from this account. The nodes and runner VMs pull with
# their instance roles, which get the policy below. autoheal_values points the
# chart's images at <registry host>/<prefix>/e4h3h0d9.

module "ecr" {
  source = "../../modules/aws/ecr"
  count  = local.create_registry ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["registry"]
  tags        = var.tags

  repository_prefix  = local.registry_prefix
  upstream_namespace = local.public_registry_namespace
}

resource "aws_iam_policy" "ecr_pull_through" {
  count = local.create_registry ? 1 : 0

  name        = "${local.id}-ecr-pull-through"
  description = "Pull Autoheal images through the ECR pull-through cache ${local.registry_prefix}."
  policy      = module.ecr[0].pull_policy_json
  tags        = merge(var.tags, { Name = "${local.id}-ecr-pull-through" })
}
