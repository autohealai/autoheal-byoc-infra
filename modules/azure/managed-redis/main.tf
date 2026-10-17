# Azure Managed Redis (the Microsoft.Cache/redisEnterprise resource). The AWS
# analogue is ElastiCache. Clients connect over TLS on port 10000 at
# <name>.<region>.redis.azure.net.
#
# Public network access is off. The composition reaches the cache through a
# private endpoint (subresource "redisEnterprise") and the
# privatelink.redis.azure.net zone, both created outside this module.
#
# Access keys stay enabled by default because the services authenticate with a
# key carried in REDIS_URL. The defaults match the smallest SKU that test
# subscriptions allow: Balanced_B0, no high availability, EnterpriseCluster
# clustering, Encrypted client protocol.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

resource "azurerm_managed_redis" "this" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = var.sku_name
  tags                = module.this.tags

  high_availability_enabled = var.high_availability_enabled
  public_network_access     = "Disabled"

  default_database {
    access_keys_authentication_enabled = var.access_keys_authentication_enabled
    client_protocol                    = var.client_protocol
    clustering_policy                  = var.clustering_policy
    eviction_policy                    = var.eviction_policy
  }
}
