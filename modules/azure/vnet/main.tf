# Azure network substrate for a BYOC-on-AKS install. The AWS analogue is
# modules/aws/vpc. Provides:
#   - VNet + four subnets: AKS nodes, PG-delegated, private endpoints, runner.
#   - A NAT gateway for the runner subnet (runner VMSS has no public IP).
#   - When temporal_ip is set, an NSG on the AKS subnet that lets only the runner
#     subnet reach that address on 7233 (Temporal) and 8083 (tool results).
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

  # When the server is created, Azure Database for PostgreSQL adds a
  # Microsoft.Storage service endpoint (its region and the paired region) to the
  # delegated subnet. Ignore it so later plans do not try to remove it.
  lifecycle {
    ignore_changes = [service_endpoints]
  }
}

resource "azurerm_subnet" "pe" {
  name                              = "snet-pe"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.subnet_pe_prefix]
  private_endpoint_network_policies = "Disabled"
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

# The Temporal load balancer address also carries the api-server-go internal
# listener on 8083, which takes sandbox tool results and checks an HMAC key on
# each result but not the caller. Only the runner subnet may reach either port
# on that address; every other source is denied. Other traffic to the AKS
# subnet keeps the default rules (VNet and Azure load balancer allowed). In-
# cluster callers use the Kubernetes services and do not cross this NSG.
resource "azurerm_network_security_group" "aks" {
  count               = var.temporal_ip == "" ? 0 : 1
  name                = "${module.this.id}-aks-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags

  security_rule {
    name                       = "allow-runner-to-temporal-address"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    source_address_prefix      = var.subnet_runner_prefix
    destination_address_prefix = var.temporal_ip
    destination_port_ranges    = ["7233", "8083"]
  }

  security_rule {
    name                       = "deny-others-to-temporal-address"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_address_prefix = var.temporal_ip
    destination_port_ranges    = ["7233", "8083"]
  }
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  count                     = var.temporal_ip == "" ? 0 : 1
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks[0].id
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
