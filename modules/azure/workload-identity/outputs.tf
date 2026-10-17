output "client_id" {
  description = "Client id stamped on the app service account (azure.workload.identity/client-id annotation). Maps to the cross-cloud output contract 'runner_identity'."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "principal_id" {
  description = "Principal (object) id of the identity, for role assignments."
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "identity_id" {
  description = "Resource ID of the user-assigned identity."
  value       = azurerm_user_assigned_identity.app.id
}

output "name" {
  description = "Name of the user-assigned identity."
  value       = azurerm_user_assigned_identity.app.name
}
