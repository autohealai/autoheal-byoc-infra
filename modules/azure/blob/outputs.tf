output "account_name" {
  description = "Storage account name. Maps to the cross-cloud output contract 'object_store' (with container)."
  value       = azurerm_storage_account.this.name
}

output "account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Primary blob endpoint URL."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_name" {
  description = "Blob container name."
  value       = azurerm_storage_container.attachments.name
}
