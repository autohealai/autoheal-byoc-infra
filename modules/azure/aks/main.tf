# AKS cluster for a BYOC install. The AWS analogue is modules/aws/eks.
#
# NOTE ON "OWN MODEL" vs AVM: per docs/MODULE_STANDARD.md, clusters are the one
# place we may wrap a pinned, verified upstream module (AVM
# avm-res-containerservice-managedcluster) instead of raw resources. That decision
# is deliberately deferred per-cluster. For now this is a faithful own-model port
# of the proven byoc cluster so the contract (outputs, create/connect) is stable;
# swapping the create path to a pinned AVM later must keep these outputs intact.
#
# Create vs connect mirrors the eks module: create_cluster = true provisions the
# cluster; false reads an existing one via a data source and creates nothing.
#
# Why a user-assigned control-plane identity (not system-assigned): AKS on a custom
# VNet requires a UAMI with Network Contributor on the VNet so the cluster can
# manage load balancers / subnet joins.
#
# OIDC issuer + workload identity are enabled explicitly so the Azure app can
# federate pod identities to Key Vault / Blob / Foundry. Naming and tags come from
# the null-label base (module.this); see label.tf.

resource "azurerm_user_assigned_identity" "cluster" {
  count               = var.create_cluster ? 1 : 0
  name                = "${module.this.id}-uami"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags
}

# The control-plane identity manages LBs/subnets during create -> Network
# Contributor on the VNet. Scoped to the VNet, not the whole RG.
resource "azurerm_role_assignment" "cluster_network" {
  count                = var.create_cluster && var.network_role_enabled ? 1 : 0
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster[0].principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  count               = var.create_cluster ? 1 : 0
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = module.this.id
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  # Keyless pod access to Azure services (Key Vault, Blob, Foundry).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    vnet_subnet_id              = var.vnet_subnet_id != "" ? var.vnet_subnet_id : null
    auto_scaling_enabled        = true
    min_count                   = var.node_min_count
    max_count                   = var.node_max_count
    temporary_name_for_rotation = "systemtmp"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster[0].id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
  }

  tags = module.this.tags

  depends_on = [azurerm_role_assignment.cluster_network]
}

# Connect mode: read the existing cluster.
data "azurerm_kubernetes_cluster" "existing" {
  count               = var.create_cluster ? 0 : 1
  name                = module.this.id
  resource_group_name = var.resource_group_name
}

locals {
  cluster = var.create_cluster ? azurerm_kubernetes_cluster.this[0] : data.azurerm_kubernetes_cluster.existing[0]
}

# Grant the kubelet identity AcrPull so nodes can pull from the customer ACR.
# Connect clusters are granted this too (idempotent) when an ACR is supplied.
resource "azurerm_role_assignment" "acr_pull" {
  count                = var.acr_id == "" ? 0 : 1
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = local.cluster.kubelet_identity[0].object_id
}
