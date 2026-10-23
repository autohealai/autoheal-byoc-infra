# Azure network substrate for a BYOC-on-AKS install. The AWS analogue is
# modules/aws/vpc. Provides:
#   - VNet + up to three subnets: AKS nodes, PG-delegated, private endpoints.
#     Each is skipped when its prefix is empty: no AKS subnet for a VNet beside a
#     cluster that runs in another VNet, and no Postgres or endpoint subnet when
#     those services use public endpoints.
#   - PostgreSQL Flexible Server private DNS zone (pre-created + VNet-linked;
#     inline creation trips a "server name + zone suffix" validation).
#   - Optional privatelink DNS zones for Blob / Key Vault / AI Foundry.
#
# Naming and tags come from the null-label base (module.this); see label.tf.
# The resource group is created by the composition and passed in, so children can
# share one teardown unit (one RG = one delete).

resource "azurerm_virtual_network" "this" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = module.this.tags
}

resource "azurerm_subnet" "aks" {
  count                = var.subnet_aks_prefix == "" ? 0 : 1
  name                 = "snet-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_aks_prefix]
}

moved {
  from = azurerm_subnet.aks
  to   = azurerm_subnet.aks[0]
}

resource "azurerm_subnet" "db" {
  count                = var.subnet_db_prefix == "" ? 0 : 1
  name                 = "snet-db"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_db_prefix]

  delegation {
    name = "pg-flexible"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  # When the server is created, Azure Database for PostgreSQL adds a
  # Microsoft.Storage service endpoint (its region and the paired region) to the
  # delegated subnet. Ignore it so later plans do not try to remove it.
  lifecycle {
    ignore_changes = [service_endpoints]
  }
}

moved {
  from = azurerm_subnet.db
  to   = azurerm_subnet.db[0]
}

resource "azurerm_subnet" "pe" {
  count                             = var.subnet_pe_prefix == "" ? 0 : 1
  name                              = "snet-pe"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.subnet_pe_prefix]
  private_endpoint_network_policies = "Disabled"
}

moved {
  from = azurerm_subnet.pe
  to   = azurerm_subnet.pe[0]
}

# Private DNS zone for PG Flexible Server, VNet-linked. Only created when a zone
# name is supplied (create installs); connect installs bring their own.
resource "azurerm_private_dns_zone" "pg" {
  count               = var.pg_private_dns_zone_name == "" ? 0 : 1
  name                = var.pg_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = module.this.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "pg" {
  count                 = var.pg_private_dns_zone_name == "" ? 0 : 1
  name                  = "pg-dnslink"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.pg[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = module.this.tags
}

# Privatelink DNS zones + VNet links for the private endpoints the composition
# creates. One zone per PaaS service type, linked to this VNet so in-VNet clients
# (AKS pods) resolve <resource>.<public-suffix> to the PE's private IP. Zones are
# created only when the matching endpoint class is enabled; installs on a brought
# network bring their own. Blob/Vault/Redis are our own resources; the Foundry zones cover AI Foundry /
# Azure OpenAI (a Cognitive account exposes records across all three suffixes).
locals {
  pe_zones = merge(
    var.private_endpoints_enabled ? {
      blob  = "privatelink.blob.core.windows.net"
      vault = "privatelink.vaultcore.azure.net"
    } : {},
    var.redis_private_endpoint_enabled ? {
      redis = "privatelink.redis.azure.net"
    } : {},
    var.foundry_private_endpoint_enabled ? {
      openai     = "privatelink.openai.azure.com"
      cognitive  = "privatelink.cognitiveservices.azure.com"
      aiservices = "privatelink.services.ai.azure.com"
    } : {},
  )
}

resource "azurerm_private_dns_zone" "pe" {
  for_each            = local.pe_zones
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = module.this.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "pe" {
  for_each              = local.pe_zones
  name                  = "${each.key}-dnslink"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.pe[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = module.this.tags
}
