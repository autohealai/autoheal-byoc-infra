output "vmss_id" {
  description = "Resource ID of the runner VMSS."
  value       = azurerm_linux_virtual_machine_scale_set.runner.id
}

output "identity_principal_id" {
  description = "Principal id of the runner's user-assigned identity (granted AcrPull when acr_pull_enabled)."
  value       = azurerm_user_assigned_identity.runner.principal_id
}

output "identity_client_id" {
  description = "Client id of the runner's user-assigned identity."
  value       = azurerm_user_assigned_identity.runner.client_id
}

output "identity_name" {
  description = "Name of the runner's user-assigned identity."
  value       = azurerm_user_assigned_identity.runner.name
}
