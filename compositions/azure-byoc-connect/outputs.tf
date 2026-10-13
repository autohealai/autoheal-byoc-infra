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

# ESO wiring for the app/install layer — identical to the create composition. The
# installer reads these to stamp the ESO controller SA's azure.workload.identity/
# client-id annotation and to wire the ClusterSecretStore (provider.azurekv,
# authType WorkloadIdentity): client_id + tenant_id + the Key Vault vault_uri.
output "eso_identity_client_id" {
  description = "Client id of the dedicated ESO identity (stamp on the ESO controller ServiceAccount)."
  value       = module.eso_identity.client_id
}

output "eso_tenant_id" {
  description = "Entra tenant id for the ClusterSecretStore provider.azurekv.tenantId."
  value       = module.eso_identity.tenant_id
}

output "eso_service_account" {
  description = "namespace/name of the federated ESO ServiceAccount (ClusterSecretStore serviceAccountRef)."
  value       = module.eso_identity.service_account
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
