# Azure network substrate for a BYOC-on-AKS install. The AWS analogue is
# modules/aws/vpc. Provides:
#   - VNet + five subnets: AKS nodes, PG-delegated, private endpoints,
#     Redis-injected, runner.
#   - A NAT gateway for the runner subnet (runner VMSS has no public IP).
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
  name                 = "snet-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_aks_prefix]
}

resource "azurerm_subnet" "db" {
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
}

resource "azurerm_subnet" "pe" {
  name                              = "snet-pe"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.subnet_pe_prefix]
  private_endpoint_network_policies = "Disabled"
}

# Dedicated subnet for Azure Cache for Redis Premium VNet INJECTION: the cache is
# placed directly into this subnet and gets a real VNet IP (no Private Endpoint,
# no privatelink DNS zone). The subnet must contain nothing else, have no
# delegation, and be sized for the SKU (a /24 is ample for P1).
resource "azurerm_subnet" "redis" {
  name                 = "snet-redis"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_redis_prefix]
}

# Dedicated subnet for the runner VMSS (Docker-out-of-Docker job runners). Kept
# off the AKS subnet so runner VMs — which execute customer workload containers —
# are isolated from cluster nodes/pods and can be governed separately (NSG, and
# the egress NAT gateway below). A VMSS needs no delegation. The internal LB does
# NOT get a subnet here — AKS projects it into the AKS subnet via a static
# loadBalancerIP annotation.
resource "azurerm_subnet" "runner" {
  name                 = "snet-runner"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_runner_prefix]
}

# Outbound egress for the runner subnet. The runner VMSS is created with no public
# IP, so all egress flows through a NAT gateway: a Standard public IP -> NAT
# gateway (idle 10 min) -> associated to snet-runner. AKS keeps its own managed
# outbound; this is runner-only, and gives a stable source IP for allowlisting.
resource "azurerm_public_ip" "runner_nat" {
  count               = var.runner_nat_enabled ? 1 : 0
  name                = "${module.this.id}-runner-nat-ip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = module.this.tags
}

resource "azurerm_nat_gateway" "runner" {
  count                   = var.runner_nat_enabled ? 1 : 0
  name                    = "${module.this.id}-runner-nat"
  resource_group_name     = var.resource_group_name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = module.this.tags
}

resource "azurerm_nat_gateway_public_ip_association" "runner" {
  count                = var.runner_nat_enabled ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.runner[0].id
  public_ip_address_id = azurerm_public_ip.runner_nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "runner" {
  count          = var.runner_nat_enabled ? 1 : 0
  subnet_id      = azurerm_subnet.runner.id
  nat_gateway_id = azurerm_nat_gateway.runner[0].id
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
# created only when the matching endpoint class is enabled; connect installs bring
# their own. Blob/Vault are our own resources; the Foundry zones cover AI Foundry /
# Azure OpenAI (a Cognitive account exposes records across all three suffixes).
locals {
  pe_zones = merge(
    var.private_endpoints_enabled ? {
      blob  = "privatelink.blob.core.windows.net"
      vault = "privatelink.vaultcore.azure.net"
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
