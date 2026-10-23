# Network: the VNet and subnets we create, or the customer's subnets read through
# data sources. The reserved proxy address is computed in locals.tf; for a
# cluster we create in a brought network, validation.tf checks it sits inside
# the AKS subnet.
#
# A brought cluster in another subscription keeps its AKS subnet there, and we
# create nothing in that subscription. Postgres and the private endpoints then go
# in a VNet of subscription_id: the customer's subnets, or a VNet we create from
# network_cidr without an AKS subnet. The customer connects the two VNets
# (required_cluster_owner_actions). On the public path (cluster_network_path =
# public) there is no such VNet: the services use public endpoints.

resource "azurerm_resource_group" "this" {
  count    = local.create_resource_group ? 1 : 0
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

locals {
  # Resource group name for everything we create. Referencing the resource, not
  # just the name, orders creation after the group.
  rg = local.create_resource_group ? azurerm_resource_group.this[0].name : local.existing.resource_group_name
}

module "vnet" {
  source = "../../modules/azure/vnet"
  count  = local.create_vnet ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location
  address_space       = [var.network_cidr]
  subnet_aks_prefix   = local.create_network ? local.created_subnets.aks : ""
  subnet_db_prefix    = local.created_subnets.postgres
  subnet_pe_prefix    = local.created_subnets.endpoint

  # The Postgres private DNS zone (only when we create Postgres) and the
  # privatelink zones for the private endpoints we create, all linked to this VNet.
  # A VNet without an AKS subnet gets its zones from the brought-network
  # resources below, which also take the customer's zones.
  pg_private_dns_zone_name       = local.create_network && local.create_postgres ? local.pg_dns_zone_name : ""
  private_endpoints_enabled      = local.create_network && var.private_endpoints_enabled
  redis_private_endpoint_enabled = local.create_network && local.create_redis
}

locals {
  # The Postgres private DNS zone name. The prefix must be a DNS label; the suffix
  # is fixed by Azure. Same name as v1.
  pg_dns_zone_name = "${var.namespace}-${var.environment}.private.postgres.database.azure.com"
}

# --- Brought network --------------------------------------------------------

# Read the AKS subnet of a cluster we create in a brought network, so
# validation.tf can check the reserved proxy address sits in it. The AKS subnet
# of a brought cluster is not read.
data "azurerm_subnet" "aks" {
  count                = local.create_cluster && !local.create_network ? 1 : 0
  name                 = split("/", var.existing_network.aks_subnet_id)[10]
  virtual_network_name = split("/", var.existing_network.aks_subnet_id)[8]
  resource_group_name  = split("/", var.existing_network.aks_subnet_id)[4]
}

# A Postgres server we create in a brought network needs a private DNS zone linked
# to its VNet. Use the customer's zone when given, otherwise create one in our
# resource group and link it.
resource "azurerm_private_dns_zone" "postgres" {
  count               = !local.create_network && local.create_postgres && !local.public_path && try(var.existing_network.postgres_private_dns_zone_id, "") == "" ? 1 : 0
  name                = local.pg_dns_zone_name
  resource_group_name = local.rg
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = length(azurerm_private_dns_zone.postgres)
  name                  = "${local.id}-pg-dnslink"
  resource_group_name   = local.rg
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = local.workload_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

# privatelink zones for the private endpoints we create in a brought network,
# for each one the customer did not pass in existing_network.private_dns_zone_ids.
# If the VNet is already linked to a zone with the same name (common with a
# central hub), pass that zone's ID instead: Azure refuses two links to zones of
# the same name.
resource "azurerm_private_dns_zone" "brought" {
  for_each            = local.brought_network_zones
  name                = local.pe_zone_names[each.key]
  resource_group_name = local.rg
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "brought" {
  for_each              = local.brought_network_zones
  name                  = "${local.id}-${each.key}-dnslink"
  resource_group_name   = local.rg
  private_dns_zone_name = azurerm_private_dns_zone.brought[each.key].name
  virtual_network_id    = local.workload_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

# For a cluster in another subscription, cluster_vnet_dns_link_enabled also links
# the zones we create to the cluster's VNet, so pods resolve Postgres and the
# private endpoints. The links are in our resource group; Azure checks that the
# deployer may join the cluster's VNet. Without it, the cluster owner resolves the
# zones (required_cluster_owner_actions).
locals {
  cluster_vnet_dns_link = var.cluster_vnet_dns_link_enabled && local.cluster_in_other_subscription && !local.public_path
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres_cluster_vnet" {
  count                 = local.cluster_vnet_dns_link ? length(azurerm_private_dns_zone.postgres) : 0
  name                  = "${local.id}-pg-cluster-dnslink"
  resource_group_name   = local.rg
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = local.brought_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cluster_vnet" {
  for_each              = local.cluster_vnet_dns_link ? local.brought_network_zones : toset([])
  name                  = "${local.id}-${each.key}-cluster-dnslink"
  resource_group_name   = local.rg
  private_dns_zone_name = azurerm_private_dns_zone.brought[each.key].name
  virtual_network_id    = local.brought_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

locals {
  postgres_private_dns_zone_id = !local.create_postgres || local.public_path ? "" : (
    local.create_network ? module.vnet[0].pg_private_dns_zone_id : (
      try(var.existing_network.postgres_private_dns_zone_id, "") != ""
      ? var.existing_network.postgres_private_dns_zone_id
      : azurerm_private_dns_zone.postgres[0].id
    )
  )
}
