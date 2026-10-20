# NOT FOR CUSTOMERS. An internal stand-in for a customer's cluster subscription
# (COP), to test examples/azure/split and examples/azure/split-public in two of
# our own subscriptions. It does what the customer's cluster owner does: one
# cluster, one namespace for us, the roles our deployer gets and the NSG rule,
# then the peering (network_path = private) or the static public IP and the
# storage service endpoint (network_path = public). See README.md.

locals {
  public            = var.network_path == "public"
  aks_subnet_prefix = cidrsubnet(var.network_cidr, 4, 0)

  # The two reserved addresses near the top of the AKS subnet, as
  # compositions/azure picks them in a network it creates. On the public path
  # Temporal is on the static public IP instead.
  temporal_ip = local.public ? azurerm_public_ip.temporal[0].ip_address : cidrhost(local.aks_subnet_prefix, -3)
  proxy_ip    = cidrhost(local.aks_subnet_prefix, -2)

  # Who may reach the Temporal address: the runner subnet over the peering, or
  # the runner's NAT address over the internet (known after the infra apply).
  runner_source = local.public ? var.runner_egress_ip : var.runner_subnet_prefix
}

resource "azurerm_resource_group" "this" {
  name     = "rg-cop-standin"
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-cop-standin"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  address_space       = [var.network_cidr]
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.aks_subnet_prefix]

  # The public path: the storage account lets this subnet in.
  service_endpoints = local.public ? ["Microsoft.Storage"] : []
}

# The public path: the static public IP for the Temporal and tool-response load
# balancers, in the node resource group, where the cluster manages its load
# balancers.
resource "azurerm_public_ip" "temporal" {
  count               = local.public ? 1 : 0
  name                = "pip-cop-standin-temporal"
  resource_group_name = module.aks.node_resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# The rule the cluster owner adds: only the runner reaches the Temporal address,
# on 7233 (Temporal) and 8083 (tool results).
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-cop-standin-aks"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  dynamic "security_rule" {
    for_each = local.runner_source == "" ? [] : [local.runner_source]
    content {
      name                       = "allow-runner-to-temporal-address"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      source_address_prefix      = security_rule.value
      destination_address_prefix = local.temporal_ip
      destination_port_ranges    = ["7233", "8083"]
    }
  }

  security_rule {
    name                       = "deny-others-to-temporal-address"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_address_prefix = local.temporal_ip
    destination_port_ranges    = ["7233", "8083"]
  }
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# OIDC issuer, workload identity, the Key Vault secrets provider add-on, Entra
# ID with Azure RBAC, and no local accounts (admin_group_object_ids is set).
module "aks" {
  source = "../../../modules/azure/aks"

  namespace   = "cop"
  environment = "standin"
  name        = "aks"

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  vnet_id                = azurerm_virtual_network.this.id
  vnet_subnet_id         = azurerm_subnet.aks.id
  node_min_count         = 2
  node_max_count         = 3
  admin_group_object_ids = var.admin_group_object_ids
  acr_pull_enabled       = false
}

resource "kubernetes_namespace_v1" "autoheal" {
  metadata {
    name = var.namespace
  }
}

# --- What our deployer gets, and nothing more --------------------------------

# Read the cluster's endpoint and CA certificate.
resource "azurerm_role_assignment" "deployer_cluster_user" {
  scope                = module.aks.cluster_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.deployer_object_id
}

# Read the AKS subnet, to check the reserved addresses.
resource "azurerm_role_assignment" "deployer_subnet_reader" {
  scope                = azurerm_subnet.aks.id
  role_definition_name = "Reader"
  principal_id         = var.deployer_object_id
}

# Admin in our namespace only. Enough for the chart's Roles and RoleBindings.
resource "azurerm_role_assignment" "deployer_namespace_admin" {
  scope                = "${module.aks.cluster_id}/namespaces/${var.namespace}"
  role_definition_name = "Azure Kubernetes Service RBAC Admin"
  principal_id         = var.deployer_object_id

  depends_on = [kubernetes_namespace_v1.autoheal]
}

# Join the VNet: the infra apply links its private DNS zones to it
# (cluster_vnet_dns_link_enabled = true), or adds the AKS subnet to the storage
# firewall (the public path).
resource "azurerm_role_assignment" "deployer_vnet_join" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = var.deployer_object_id
}

# --- Peering, after the infra apply (private path only) -----------------------

resource "azurerm_virtual_network_peering" "cop_to_sre" {
  count                     = !local.public && var.sre_vnet_id != "" ? 1 : 0
  name                      = "cop-to-sre"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = var.sre_vnet_id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "sre_to_cop" {
  provider                  = azurerm.sre
  count                     = !local.public && var.sre_vnet_id != "" ? 1 : 0
  name                      = "sre-to-cop"
  resource_group_name       = split("/", var.sre_vnet_id)[4]
  virtual_network_name      = split("/", var.sre_vnet_id)[8]
  remote_virtual_network_id = azurerm_virtual_network.this.id
  allow_forwarded_traffic   = true
}
