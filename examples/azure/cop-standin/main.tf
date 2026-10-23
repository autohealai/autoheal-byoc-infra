# NOT FOR CUSTOMERS. An internal stand-in for a customer's cluster subscription
# (COP), to test examples/azure/split and examples/azure/split-public in two of
# our own subscriptions. It does what the customer's cluster owner does: one
# cluster, one namespace for us and the roles our deployer gets, then the
# peering (network_path = private) or the proxy's static public IP, its NSG rule
# and the storage service endpoint (network_path = public). See README.md.

locals {
  public            = var.network_path == "public"
  aks_subnet_prefix = cidrsubnet(var.network_cidr, 4, 0)

  # The reserved address near the top of the AKS subnet, as compositions/azure
  # picks it in a network it creates. On the public path the proxy is on a
  # static public IP instead.
  proxy_ip = local.public ? azurerm_public_ip.proxy[0].ip_address : cidrhost(local.aks_subnet_prefix, -2)
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

# The public path: the static public IP for the Autoheal proxy, which users and
# webhooks reach. It is in the node resource group, where the cluster manages its
# load balancers.
resource "azurerm_public_ip" "proxy" {
  count               = local.public ? 1 : 0
  name                = "pip-cop-standin-proxy"
  resource_group_name = module.aks.node_resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# The rule the cluster owner adds on the public path: everyone reaches the proxy
# on 443 and 80.
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-cop-standin-aks"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  dynamic "security_rule" {
    for_each = local.public ? [local.proxy_ip] : []
    content {
      name                       = "allow-internet-to-proxy"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      source_address_prefix      = "Internet"
      destination_address_prefix = security_rule.value
      destination_port_ranges    = ["443", "80"]
    }
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

# Admin in our namespace only. Enough for the chart's Roles and RoleBindings.
resource "azurerm_role_assignment" "deployer_namespace_admin" {
  scope                = "${module.aks.cluster_id}/namespaces/${var.namespace}"
  role_definition_name = "Azure Kubernetes Service RBAC Admin"
  principal_id         = var.deployer_object_id

  depends_on = [kubernetes_namespace_v1.autoheal]
}

# Join the VNet, on the private path: the infra apply links its private DNS
# zones to it (cluster_vnet_dns_link_enabled = true). On the public path the
# stand-in's operator adds the storage subnet rule instead (README.md).
resource "azurerm_role_assignment" "deployer_vnet_join" {
  count                = local.public ? 0 : 1
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
