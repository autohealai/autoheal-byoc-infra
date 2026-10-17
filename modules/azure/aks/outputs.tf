output "cluster_name" {
  description = "AKS cluster name. Maps to the cross-cloud output contract 'cluster_name'."
  value       = local.cluster.name
}

output "cluster_id" {
  description = "Resource ID of the cluster."
  value       = local.cluster.id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Entra Workload Identity federated credentials (feeds modules/azure/workload-identity)."
  value       = local.cluster.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Kubelet identity object id (granted AcrPull for node image pulls)."
  value       = local.cluster.kubelet_identity[0].object_id
}

output "identity_principal_id" {
  description = "Principal id of the control-plane user-assigned identity (create mode), or empty in connect mode."
  value       = var.create_cluster ? azurerm_user_assigned_identity.cluster[0].principal_id : ""
}

output "identity_name" {
  description = "Name of the control-plane user-assigned identity (create mode), or empty in connect mode."
  value       = var.create_cluster ? azurerm_user_assigned_identity.cluster[0].name : ""
}

output "node_resource_group" {
  description = "Auto-managed node resource group (MC_*)."
  value       = local.cluster.node_resource_group
}

# Kubeconnection fields for a downstream kubernetes/helm provider (exec auth via
# kubelogin). These come from the AAD-integrated kube_config block.
output "host" {
  description = "Kubernetes API server host."
  value       = local.cluster.kube_config[0].host
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64)."
  value       = local.cluster.kube_config[0].cluster_ca_certificate
  sensitive   = true
}
