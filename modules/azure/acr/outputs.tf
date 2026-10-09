output "acr_id" {
  description = "Resource ID of the registry (grant AcrPull on this in aks / runner-vmss / workload-identity)."
  value       = azurerm_container_registry.this.id
}

output "acr_name" {
  description = "Registry name (for `az acr login -n`)."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Registry login server (e.g. crautohealplay.azurecr.io). Maps to the cross-cloud output contract 'registry'."
  value       = azurerm_container_registry.this.login_server
}
