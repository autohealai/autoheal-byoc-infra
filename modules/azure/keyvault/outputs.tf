output "key_vault_id" {
  description = "Resource ID of the Key Vault."
  value       = azurerm_key_vault.this.id
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "Vault URI the ESO ClusterSecretStore points at. Maps to the cross-cloud output contract 'secret_store_uri'."
  value       = azurerm_key_vault.this.vault_uri
}
