output "client_id" {
  description = "Client id of the ESO identity. The app/install layer stamps this on the ESO controller ServiceAccount (azure.workload.identity/client-id annotation)."
  value       = azurerm_user_assigned_identity.eso.client_id
}

output "principal_id" {
  description = "Principal (object) id of the ESO identity, for additional role assignments if needed."
  value       = azurerm_user_assigned_identity.eso.principal_id
}

output "identity_id" {
  description = "Resource ID of the ESO user-assigned identity."
  value       = azurerm_user_assigned_identity.eso.id
}

output "tenant_id" {
  description = "Entra tenant id of the ESO identity. Feeds the ClusterSecretStore provider.azurekv.tenantId."
  value       = azurerm_user_assigned_identity.eso.tenant_id
}

output "service_account" {
  description = "namespace/name of the federated ESO ServiceAccount, so the app layer wires the ClusterSecretStore serviceAccountRef consistently."
  value       = "${var.eso_namespace}/${var.eso_service_account}"
}
