# The cross-cloud output contract. compositions/aws-byoc emits the SAME names, so
# the Autoheal app install is cloud-agnostic (docs/MODULE_STANDARD.md §8).

output "cluster_name" {
  description = "AKS cluster name."
  value       = module.aks.cluster_name
}

output "postgres_host" {
  description = "PostgreSQL Flexible Server FQDN (private)."
  value       = module.postgres.host
}

output "redis_endpoint" {
  description = "Redis endpoint (host:ssl_port), Premium VNet-injected."
  value       = module.redis.endpoint
}

output "object_store" {
  description = "Blob container reference (account/container) for attachments."
  value       = "${module.blob.account_name}/${module.blob.container_name}"
}

output "secret_store_uri" {
  description = "Key Vault URI the ESO ClusterSecretStore points at."
  value       = module.keyvault.vault_uri
}

output "registry" {
  description = "Container registry login server."
  value       = module.acr.login_server
}

output "runner_identity" {
  description = "App workload identity client id (stamped on the app service account)."
  value       = module.workload_identity.client_id
}

# -- Extras the app install / later steps need (not part of the shared contract) --

output "resource_group_name" {
  description = "Resource group the stack lives in."
  value       = azurerm_resource_group.this.name
}

output "oidc_issuer_url" {
  description = "AKS OIDC issuer URL (for any further workload-identity federation)."
  value       = module.aks.oidc_issuer_url
}

output "acr_id" {
  description = "ACR resource id (the runner VMSS step grants its identity AcrPull here)."
  value       = module.acr.acr_id
}

output "runner_subnet_id" {
  description = "Runner subnet id (fed to the separate runner-vmss apply)."
  value       = module.vnet.subnet_runner_id
}

output "kube_host" {
  description = "Kubernetes API server host."
  value       = module.aks.host
  sensitive   = true
}
