# AKS: the cluster we create, or the customer's cluster read through a data source.
#
# A created cluster has the OIDC issuer, workload identity and the Key Vault
# secrets provider (CSI driver) add-on on, and Entra integration with Azure RBAC.
# Its control-plane identity gets Network Contributor on the VNet we create, or on
# the AKS subnet of a brought network. That grant is what lets the chart pin the
# Temporal and proxy internal load balancers to the reserved addresses.
#
# A brought cluster is never managed here. validation.tf checks it has the
# add-on and the OIDC issuer.

module "aks" {
  source = "../../modules/azure/aks"
  count  = local.create_cluster ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location

  vnet_id              = local.create_network ? module.vnet[0].vnet_id : var.existing_network.aks_subnet_id
  vnet_subnet_id       = local.aks_subnet_id
  network_role_enabled = var.create_role_assignments
  kubernetes_version   = var.kubernetes_version
  node_vm_size         = var.aks_node_size
  node_min_count       = var.aks_node_count
  node_max_count       = max(var.aks_node_max_count, var.aks_node_count)

  # Nodes pull from the registry when there is one. Gated on plan-time inputs, not
  # on the registry ID, which is known only after apply when we create it.
  acr_id           = local.acr_id
  acr_pull_enabled = local.acr_enabled && var.create_role_assignments

  admin_group_object_ids          = var.admin_group_object_ids
  tenant_id                       = var.aks_admin_tenant_id
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
  private_cluster_enabled         = var.private_cluster_enabled

  entra_integration_enabled          = true
  key_vault_secrets_provider_enabled = true
}

data "azurerm_kubernetes_cluster" "existing" {
  count               = local.create_cluster ? 0 : 1
  name                = local.existing.aks.name
  resource_group_name = local.existing.aks.rg
}

locals {
  # Connection details for the app composition. The CA certificate and endpoint
  # are not secret, so they leave the sensitive marking of kube_config behind.
  cluster_endpoint = local.create_cluster ? try(nonsensitive(module.aks[0].host), module.aks[0].host) : try(
    nonsensitive(data.azurerm_kubernetes_cluster.existing[0].kube_config[0].host),
    data.azurerm_kubernetes_cluster.existing[0].kube_config[0].host,
    "",
  )
  cluster_ca_certificate = local.create_cluster ? try(nonsensitive(module.aks[0].cluster_ca_certificate), module.aks[0].cluster_ca_certificate) : try(
    nonsensitive(data.azurerm_kubernetes_cluster.existing[0].kube_config[0].cluster_ca_certificate),
    data.azurerm_kubernetes_cluster.existing[0].kube_config[0].cluster_ca_certificate,
    "",
  )
}
