# Private endpoints for the blocks we create. They go in the endpoint subnet: ours,
# or existing_network.endpoint_subnet_id. Their privatelink DNS zones come from
# the vnet module for a network we create, and from
# existing_network.private_dns_zone_ids or network.tf for a brought one or for a
# VNet we create beside a cluster in another subscription.
#
#   - Blob and both Key Vaults (install and runtime): when
#     private_endpoints_enabled. This is the recommended runtime path for
#     in-cluster pods. The two vaults share the privatelink.vaultcore zone.
#   - Azure Managed Redis: always, except on the public path
#     (cluster_network_path = public), where it is public instead.
#
# A brought storage account, vault or Redis keeps whatever private access its
# owner set up; we add no endpoint to it.
#
# In a brought network without endpoint_subnet_id no endpoint is planned, so the
# plan stops on the plain message in validation.tf.

locals {
  endpoint_subnet_given = local.create_vnet || try(var.existing_network.endpoint_subnet_id, "") != ""
}

module "pe_blob" {
  source = "../../modules/azure/private-endpoint"
  count  = local.pe_blob_enabled && local.endpoint_subnet_given ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["blob"]
  tags        = var.tags

  resource_group_name  = local.rg
  location             = var.location
  subnet_id            = local.endpoint_subnet_id
  target_resource_id   = module.blob[0].account_id
  subresource_names    = ["blob"]
  private_dns_zone_ids = [local.pe_zone_ids["blob"]]
}

module "pe_vault" {
  source = "../../modules/azure/private-endpoint"
  count  = local.pe_vault_enabled && local.endpoint_subnet_given ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["vault"]
  tags        = var.tags

  resource_group_name  = local.rg
  location             = var.location
  subnet_id            = local.endpoint_subnet_id
  target_resource_id   = module.keyvault[0].key_vault_id
  subresource_names    = ["vault"]
  private_dns_zone_ids = [local.pe_zone_ids["vault"]]
}

module "pe_runtime_vault" {
  source = "../../modules/azure/private-endpoint"
  count  = local.pe_runtime_vault_enabled && local.endpoint_subnet_given ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["vault", "rt"]
  tags        = var.tags

  resource_group_name  = local.rg
  location             = var.location
  subnet_id            = local.endpoint_subnet_id
  target_resource_id   = module.runtime_keyvault[0].key_vault_id
  subresource_names    = ["vault"]
  private_dns_zone_ids = [local.pe_zone_ids["vault"]]
}

module "pe_redis" {
  source = "../../modules/azure/private-endpoint"
  count  = local.pe_redis_enabled && local.endpoint_subnet_given ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["redis"]
  tags        = var.tags

  resource_group_name  = local.rg
  location             = var.location
  subnet_id            = local.endpoint_subnet_id
  target_resource_id   = module.redis[0].id
  subresource_names    = ["redisEnterprise"]
  private_dns_zone_ids = [local.pe_zone_ids["redis"]]
}
