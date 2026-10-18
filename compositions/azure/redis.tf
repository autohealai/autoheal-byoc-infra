# Redis (optional): the Azure Managed Redis we create, reached only through a
# private endpoint, or the customer's Azure Managed Redis or Azure Cache for Redis
# read through a data source. The access key goes into the vault (secrets.tf).

module "redis" {
  source = "../../modules/azure/managed-redis"
  count  = local.create_redis ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["redis"]
  tags        = var.tags

  resource_group_name       = local.rg
  location                  = var.location
  sku_name                  = var.redis_sku
  high_availability_enabled = var.redis_high_availability_enabled
}

data "azurerm_managed_redis" "existing" {
  count               = local.brought_redis_kind == "managed" ? 1 : 0
  name                = local.existing.redis.name
  resource_group_name = local.existing.redis.rg
}

data "azurerm_redis_cache" "existing" {
  count               = local.brought_redis_kind == "cache" ? 1 : 0
  name                = local.existing.redis.name
  resource_group_name = local.existing.redis.rg
}
