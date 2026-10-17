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

# Used to default the tenant for managed-AAD RBAC when the operator supplies admin
# groups but not an explicit tenant_id.
data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "cluster" {
  count               = var.create_cluster ? 1 : 0
  name                = "${module.this.id}-uami"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags
}

# The control-plane identity manages LBs/subnets during create -> Network
# Contributor on the VNet (or only the node subnet when the network is brought).
# This is also what lets the cluster place an internal load balancer on a pinned
# address in the node subnet.
resource "azurerm_role_assignment" "cluster_network" {
  count                = var.create_cluster && var.network_role_enabled ? 1 : 0
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster[0].principal_id
}

#trivy:ignore:AVD-AZU-0041 Operator-gated via api_server_authorized_ip_ranges (below); no safe default CIDR for an admin/CI-facing API server. Private access unaffected.
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

  # API server exposure. Default is a public endpoint (optionally CIDR-restricted via
  # api_server_access_profile below). private_cluster_enabled = true provisions a fully
  # private control plane reachable only from the VNet / peered networks — whatever runs
  # kubectl or Terraform must then have in-VNet (or peered) connectivity.
  private_cluster_enabled = var.private_cluster_enabled

  # Kubernetes RBAC authorization is always on. Entra integration with Azure RBAC is on
  # by default (entra_integration_enabled), so callers log in with kubelogin and
  # cluster access is governed by Entra identities and Azure role assignments. It is
  # also turned on whenever admin_group_object_ids is set.
  role_based_access_control_enabled = true

  # Disable the local (static-certificate) admin accounts once Entra is wired up;
  # otherwise `az aks get-credentials --admin` hands out a cluster-admin kubeconfig that
  # bypasses Entra entirely. Only disabled when admin groups are supplied, so a cluster
  # brought up without Entra configured does not lock itself out of all access.
  local_account_disabled = length(var.admin_group_object_ids) > 0

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.entra_integration_enabled || length(var.admin_group_object_ids) > 0 ? [1] : []
    content {
      azure_rbac_enabled     = true
      tenant_id              = var.tenant_id != "" ? var.tenant_id : data.azurerm_client_config.current.tenant_id
      admin_group_object_ids = var.admin_group_object_ids
    }
  }

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

  # Key Vault secrets provider (CSI driver) add-on. The chart mounts the vault with a
  # SecretProviderClass that authenticates through workload identity, so the add-on's
  # own identity needs no grants.
  dynamic "key_vault_secrets_provider" {
    for_each = var.key_vault_secrets_provider_enabled ? [1] : []
    content {
      secret_rotation_enabled  = true
      secret_rotation_interval = var.secret_rotation_interval
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    # Enforce Kubernetes NetworkPolicy via Cilium (matches the cilium data plane).
    network_policy = "cilium"
  }

  # Restrict the public API server to operator-supplied CIDRs. Emitted only when
  # api_server_authorized_ip_ranges is non-empty and the cluster is public: an AKS API
  # server is reached by admins/CI from varying networks, so there is no universally-safe
  # default CIDR — the restriction is inherently operator-gated per deployment (production
  # must set it, or use private_cluster_enabled). A private cluster rejects an authorized
  # IP list, so this block is suppressed in that case.
  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 && !var.private_cluster_enabled ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
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
  # Each attribute is taken from the created or the read cluster on its own.
  # one() over the whole cluster object would mark every attribute sensitive,
  # because kube_config is, and a root output built from the name would then
  # fail the plan. Only one of the two lists has an element. A value is null,
  # not an error, when both are empty (the module's resources are skipped under
  # override_module) or when a nested block such as kube_config is still empty.
  cluster_name = one(concat(
    azurerm_kubernetes_cluster.this[*].name,
    data.azurerm_kubernetes_cluster.existing[*].name,
  ))
  cluster_id = one(concat(
    azurerm_kubernetes_cluster.this[*].id,
    data.azurerm_kubernetes_cluster.existing[*].id,
  ))
  oidc_issuer_url = one(concat(
    azurerm_kubernetes_cluster.this[*].oidc_issuer_url,
    data.azurerm_kubernetes_cluster.existing[*].oidc_issuer_url,
  ))
  kubelet_identity_object_id = one(flatten(concat(
    azurerm_kubernetes_cluster.this[*].kubelet_identity[*].object_id,
    data.azurerm_kubernetes_cluster.existing[*].kubelet_identity[*].object_id,
  )))
  node_resource_group = one(concat(
    azurerm_kubernetes_cluster.this[*].node_resource_group,
    data.azurerm_kubernetes_cluster.existing[*].node_resource_group,
  ))
  kube_host = one(flatten(concat(
    azurerm_kubernetes_cluster.this[*].kube_config[*].host,
    data.azurerm_kubernetes_cluster.existing[*].kube_config[*].host,
  )))
  kube_ca_certificate = one(flatten(concat(
    azurerm_kubernetes_cluster.this[*].kube_config[*].cluster_ca_certificate,
    data.azurerm_kubernetes_cluster.existing[*].kube_config[*].cluster_ca_certificate,
  )))
}

# Grant the kubelet identity AcrPull so nodes can pull from the customer ACR.
# Gated on a plan-time bool, not on acr_id: a composition that creates its own ACR
# passes module.acr.acr_id (known only after apply), which cannot be used in count.
resource "azurerm_role_assignment" "acr_pull" {
  count                = var.acr_pull_enabled ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = local.kubelet_identity_object_id
}
