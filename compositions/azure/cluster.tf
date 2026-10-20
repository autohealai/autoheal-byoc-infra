# AKS: the cluster we create, or the customer's cluster read through a data source.
#
# A created cluster has the OIDC issuer, workload identity and the Key Vault
# secrets provider (CSI driver) add-on on, and Entra integration with Azure RBAC.
# Its control-plane identity gets Network Contributor on the VNet we create, or on
# the AKS subnet of a brought network. That grant is what lets the chart pin the
# Temporal and proxy internal load balancers to the reserved addresses.
#
# A brought cluster is never managed here. validation.tf checks it has the
# add-on and the OIDC issuer. It may be in another subscription of the same
# tenant; it is read there through the azurerm.cluster provider.

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

# Read in the cluster's subscription, which may differ from subscription_id.
data "azurerm_kubernetes_cluster" "existing" {
  provider            = azurerm.cluster
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

# --- What the owner of a brought cluster does -------------------------------

# Lines for the required_cluster_owner_actions output, in the style of
# required_role_assignments. Empty for a cluster we create. The network and DNS
# lines apply only to a cluster in another subscription, where we create
# nothing next to the cluster.
locals {
  cluster_namespace   = var.service_accounts.namespace
  aks_subnet_label    = local.create_network ? "" : "${split("/", var.existing_network.aks_subnet_id)[8]}/${split("/", var.existing_network.aks_subnet_id)[10]}"
  node_resource_group = try(data.azurerm_kubernetes_cluster.existing[0].node_resource_group, "")
  # The runner's NAT address, which the public load balancers let in.
  runner_egress_ip = local.create_vnet ? module.vnet[0].runner_nat_public_ip : ""

  runner_source = local.public_path ? "the runner VMs' outbound address ${local.runner_egress_ip}" : local.create_vnet ? "the runner subnet (${local.created_subnets.runner})" : (
    local.create_network ? "" : "the runner subnet ${try("${split("/", var.existing_network.runner_subnet_id)[8]}/${split("/", var.existing_network.runner_subnet_id)[10]}", "")}"
  )

  # Private DNS zones the cluster's VNet must resolve, each mapped to whether we
  # created it (and so link it when cluster_vnet_dns_link_enabled).
  cluster_dns_zones = !local.cluster_in_other_subscription || local.public_path ? {} : merge(
    { for k in local.pe_zones_needed : local.pe_zone_names[k] => contains(local.brought_network_zones, k) },
    local.create_postgres ? {
      (try(var.existing_network.postgres_private_dns_zone_id, "") != "" ? lower(split("/", var.existing_network.postgres_private_dns_zone_id)[8]) : local.pg_dns_zone_name) = (
        try(var.existing_network.postgres_private_dns_zone_id, "") == ""
      )
    } : {},
  )
  cluster_dns_zones_to_resolve = sort([for name, ours in local.cluster_dns_zones : name if !(ours && local.cluster_vnet_dns_link)])
  cluster_dns_zones_we_link    = sort([for name, ours in local.cluster_dns_zones : name if ours && local.cluster_vnet_dns_link])

  cluster_owner_actions = local.create_cluster ? [] : concat(
    [
      "Azure Kubernetes Service Cluster User Role on ${local.cluster_name} for the deployer (object ID ${local.deployer_object_id}): the plan reads the cluster's endpoint and CA certificate",
      "Reader on the AKS subnet ${local.aks_subnet_label} for the deployer (object ID ${local.deployer_object_id}): the plan checks that the reserved addresses are inside it",
      "The namespace ${local.cluster_namespace} in ${local.cluster_name}. When the deployer may not create namespaces, create it and set create_namespace = false in compositions/app",
      "A Kubernetes role for the deployer (object ID ${local.deployer_object_id}) in the namespace ${local.cluster_namespace}: Azure Kubernetes Service RBAC Admin at ${var.existing_aks_cluster_id}/namespaces/${local.cluster_namespace} with Azure RBAC, or a RoleBinding to the admin ClusterRole with Kubernetes RBAC",
      "The OIDC issuer, workload identity and the Key Vault secrets provider add-on on ${local.cluster_name}",
      "An NSG rule on the AKS subnet ${local.aks_subnet_label}: allow ${local.runner_source} to ${local.temporal_ip} on TCP 7233 and 8083, and deny every other source to that address on those ports",
    ],
    local.cluster_in_other_subscription && !local.public_path ? [
      "A network path between ${local.brought_vnet_id} and ${local.workload_vnet_id}: VNet peering in both directions, or both VNets through your hub. Pods reach Postgres, Redis, storage and the vaults over it, and the runner VMs reach ${local.temporal_ip}",
    ] : [],
    local.public_path ? [
      "A Standard static public IP ${local.temporal_ip} in ${local.node_resource_group}, the node resource group of ${local.cluster_name}: the public Temporal and tool-response load balancers${local.proxy_shares_temporal_ip ? " and the Autoheal proxy" : ""} use it",
      "The Microsoft.Storage service endpoint on the AKS subnet ${local.aks_subnet_label}, and Network Contributor or a role with Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action on it for the deployer (object ID ${local.deployer_object_id}): the storage account lets that subnet in",
      "Fixed public outbound addresses for ${local.cluster_name}: ${join(", ", var.workload_egress_ip_ranges)}. Postgres and the Key Vaults let in only them",
    ] : [],
    local.public_edge && !local.proxy_shares_temporal_ip ? [
      "A Standard static public IP ${local.proxy_ip} in ${local.node_resource_group}, the node resource group of ${local.cluster_name}: the Autoheal proxy's load balancer uses it",
    ] : [],
    local.public_edge ? [
      "An NSG rule on the AKS subnet ${local.aks_subnet_label}: allow your users and webhook senders, or the internet, to ${local.proxy_ip} on TCP 443 and 80, the public address of the Autoheal proxy",
    ] : [],
    !local.public_edge && local.cluster_in_other_subscription && local.proxy_ip != "" ? [
      "A path for users to ${local.proxy_ip} on TCP 443, the address of the Autoheal proxy",
    ] : [],
    length(local.cluster_dns_zones_we_link) > 0 ? [
      "Network Contributor, or a role with Microsoft.Network/virtualNetworks/join/action, on ${local.brought_vnet_id} for the deployer (object ID ${local.deployer_object_id}): the apply links ${join(", ", local.cluster_dns_zones_we_link)} to that VNet",
    ] : [],
    length(local.cluster_dns_zones_to_resolve) > 0 ? [
      "Private DNS resolution in ${split("/", local.brought_vnet_id)[8]} for ${join(", ", local.cluster_dns_zones_to_resolve)}: link the zones to that VNet, or forward them from your DNS servers",
    ] : [],
    local.acr_enabled ? [
      "AcrPull on ${local.acr_name} for the kubelet identity of ${local.cluster_name} (object ID ${local.kubelet_object_id})",
    ] : [],
  )
}
