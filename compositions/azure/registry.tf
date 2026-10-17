# Container registry (optional). Images come from the public registry by default,
# so we create none. Set create_registry = true to create one (v1 installs keep
# theirs this way), or existing_acr_id to use the customer's mirror. When there is
# a registry, the AKS nodes and the runner VMs get AcrPull on it.

module "acr" {
  source = "../../modules/azure/acr"
  count  = local.create_registry ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location
  sku                 = var.acr_sku
}
