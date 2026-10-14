# The cross-cloud output contract. compositions/aws-byoc emits the SAME names, so
# the Autoheal app install is cloud-agnostic (docs/MODULE_STANDARD.md §8).
#
# NOTE: there is intentionally no "redis_endpoint" output on Azure. Redis runs
# in-cluster (a StatefulSet shipped by the app Helm chart) at a fixed service DNS
# name, so the app does not learn it from infra. Customers who bring their own
# managed Redis use compositions/azure-byoc-connect, which still emits it.

output "cluster_name" {
  description = "AKS cluster name."
  value       = module.aks.cluster_name
}

output "postgres_host" {
  description = "PostgreSQL Flexible Server FQDN (private)."
  value       = module.postgres.host
}

output "object_store" {
  description = "Blob container reference (account/container) for attachments."
  value       = "${module.blob.account_name}/${module.blob.container_name}"
}

output "blob_endpoint" {
  description = "Primary blob endpoint of the storage account (https://<account>.blob.core.windows.net/). The installer passes it to api-server-go as GIT_REGISTRY_AZURE_STORAGE_ACCOUNT_URL."
  value       = module.blob.blob_endpoint
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

output "acr_name" {
  description = "ACR registry name (the runner VMSS stage-2 apply needs this alongside acr_id)."
  value       = module.acr.acr_name
}

# ESO wiring for the app/install layer. The operator install + ClusterSecretStore +
# ExternalSecrets live in the chart/install-aks.sh, which reads these to wire the
# ClusterSecretStore (provider.azurekv, authType WorkloadIdentity) and to stamp the
# ESO controller ServiceAccount's azure.workload.identity/client-id annotation.
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

output "runner_subnet_id" {
  description = "Runner subnet id (fed to the separate runner-vmss apply)."
  value       = module.vnet.subnet_runner_id
}

output "kube_host" {
  description = "Kubernetes API server host."
  value       = module.aks.host
  sensitive   = true
}
