output "client_id" {
  description = "Client ID of the identity. The chart puts it in the SecretProviderClass (global.infra.identities.secrets)."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "Principal (object) ID of the identity, for role assignments made outside this module."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "identity_id" {
  description = "Resource ID of the user-assigned identity."
  value       = azurerm_user_assigned_identity.this.id
}

output "name" {
  description = "Name of the user-assigned identity."
  value       = azurerm_user_assigned_identity.this.name
}

output "tenant_id" {
  description = "Entra tenant ID of the identity."
  value       = azurerm_user_assigned_identity.this.tenant_id
}
