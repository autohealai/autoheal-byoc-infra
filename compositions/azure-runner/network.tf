# Network: a VNet of our own with the subnet snet-runner and a NAT gateway with
# a static public IP, or the customer's subnet (existing_subnet_id). Either way
# the VMs get no public IP and nothing connects into them.
#
# The VNet we create is not connected to anything. The network owner connects it
# privately to the cluster's VNet, through their hub or a peering, and allows
# the runner subnet to the Temporal address (required_network_owner_actions).
# Outbound traffic to the image registry, git hosts and tool endpoints leaves
# through the NAT gateway's IP (egress_ip), unless the owner's routes send it
# through their firewall.

resource "azurerm_virtual_network" "runner" {
  count               = local.create_network ? 1 : 0
  name                = "${local.id}-runner"
  resource_group_name = local.rg
  location            = var.location
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "runner" {
  count                = local.create_network ? 1 : 0
  name                 = "snet-runner"
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.runner[0].name
  address_prefixes     = [var.address_space]
}

resource "azurerm_public_ip" "runner_nat" {
  count               = local.create_network ? 1 : 0
  name                = "${local.id}-runner-nat-ip"
  resource_group_name = local.rg
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "runner" {
  count                   = local.create_network ? 1 : 0
  name                    = "${local.id}-runner-nat"
  resource_group_name     = local.rg
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "runner" {
  count                = local.create_network ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.runner[0].id
  public_ip_address_id = azurerm_public_ip.runner_nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "runner" {
  count          = local.create_network ? 1 : 0
  subnet_id      = azurerm_subnet.runner[0].id
  nat_gateway_id = azurerm_nat_gateway.runner[0].id
}

# The customer's subnet, read for its address range, which the network rule
# names. It is in subscription_id, not the cluster's.
data "azurerm_subnet" "existing" {
  count                = local.create_network ? 0 : 1
  name                 = split("/", var.existing_subnet_id)[10]
  virtual_network_name = split("/", var.existing_subnet_id)[8]
  resource_group_name  = split("/", var.existing_subnet_id)[4]
}

locals {
  # The subnet ID from the NAT association, so the VMs boot with outbound access.
  subnet_id   = local.create_network ? azurerm_subnet_nat_gateway_association.runner[0].subnet_id : var.existing_subnet_id
  subnet_cidr = local.create_network ? var.address_space : data.azurerm_subnet.existing[0].address_prefixes[0]
  egress_ip   = local.create_network ? azurerm_public_ip.runner_nat[0].ip_address : null
}
