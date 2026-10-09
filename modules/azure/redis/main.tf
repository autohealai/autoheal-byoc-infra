# Azure Cache for Redis, Premium + VNet INJECTION. The AWS analogue is
# modules/aws/elasticache. BYOC decision (see docs + repo memory): Premium,
# injected directly into a dedicated subnet — NOT the newer "Managed Redis"
# (Enterprise) and NOT a Private Endpoint. Injection gives the cache a real IP in
# modules/azure/vnet's snet-redis, so in-VNet clients (AKS pods) reach it with no
# privatelink DNS zone and no public endpoint.
#
# VNet injection is a Premium-only, create-time-immutable property: the subnet must
# be dedicated (nothing else in it), undelegated, and the cache cannot later move
# subnets without a recreate. Non-SSL port stays closed; TLS >= 1.2.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

resource "azurerm_redis_cache" "this" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location

  sku_name    = "Premium"
  family      = "P"
  capacity    = var.capacity
  subnet_id   = var.subnet_id
  shard_count = var.shard_count

  non_ssl_port_enabled          = false
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  redis_version                 = var.redis_version

  # Pin a private IP in the injected subnet when asked (lets the app config be
  # written before apply); null = Azure picks a free address in snet-redis.
  private_static_ip_address = var.private_static_ip_address != "" ? var.private_static_ip_address : null

  redis_configuration {
    maxmemory_policy = var.maxmemory_policy
  }

  tags = module.this.tags

  lifecycle {
    # subnet_id and the injected private IP are immutable; guard against a plan
    # that would destroy/recreate the cache (and drop all keys) on a drift read.
    ignore_changes = [private_static_ip_address]
  }
}
