# The SAME cross-cloud output contract as compositions/azure-byoc (create), read
# from the existing resources. The Autoheal app install consumes these identically
# whether infra was created by us or connected to.

output "cluster_name" {
  description = "Existing AKS cluster name."
  value       = data.azurerm_kubernetes_cluster.existing.name
}

output "postgres_host" {
  description = "Existing PostgreSQL Flexible Server FQDN (private)."
  value       = data.azurerm_postgresql_flexible_server.existing.fqdn
}

output "redis_endpoint" {
  description = "Existing Redis endpoint (host:ssl_port)."
  value       = "${data.azurerm_redis_cache.existing.hostname}:${data.azurerm_redis_cache.existing.ssl_port}"
}

output "object_store" {
  description = "Blob container reference (account/container) for attachments."
  value       = "${data.azurerm_storage_account.existing.name}/${var.storage_container_name}"
}

output "secret_store_uri" {
  description = "Existing Key Vault URI the ESO ClusterSecretStore points at."
  value       = data.azurerm_key_vault.existing.vault_uri
}

output "registry" {
  description = "Existing container registry login server."
  value       = data.azurerm_container_registry.existing.login_server
}

output "runner_identity" {
  description = "App workload identity client id this composition created (stamped on the app service account)."
  value       = module.workload_identity.client_id
}

# -- Extras the app install / later steps need (not part of the shared contract) --

output "resource_group_name" {
  description = "Resource group the connected stack lives in."
  value       = var.resource_group_name
}

output "oidc_issuer_url" {
  description = "Existing AKS OIDC issuer URL."
  value       = data.azurerm_kubernetes_cluster.existing.oidc_issuer_url
}

output "acr_id" {
  description = "Existing ACR resource id."
  value       = data.azurerm_container_registry.existing.id
}

output "kube_host" {
  description = "Kubernetes API server host of the existing cluster."
  value       = data.azurerm_kubernetes_cluster.existing.kube_config[0].host
  sensitive   = true
}
