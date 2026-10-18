output "vnet_id" {
  description = "Resource ID of the VNet."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the VNet."
  value       = azurerm_virtual_network.this.name
}

output "subnet_aks_id" {
  description = "Subnet ID for AKS nodes/pods."
  value       = azurerm_subnet.aks.id
}

output "subnet_db_id" {
  description = "Subnet ID delegated to PostgreSQL Flexible Server."
  value       = azurerm_subnet.db.id
}

output "subnet_pe_id" {
  description = "Subnet ID for private endpoints."
  value       = azurerm_subnet.pe.id
}

output "subnet_runner_id" {
  description = "Subnet ID for the runner VMSS."
  value       = azurerm_subnet.runner.id
}

output "aks_nsg_id" {
  description = "Resource ID of the AKS subnet NSG, or empty when temporal_ip is not set."
  value       = var.temporal_ip == "" ? "" : azurerm_network_security_group.aks[0].id
}

output "aks_nsg_name" {
  description = "Name of the AKS subnet NSG, or empty when temporal_ip is not set."
  value       = var.temporal_ip == "" ? "" : azurerm_network_security_group.aks[0].name
}

output "runner_nat_public_ip" {
  description = "Static egress IP of the runner subnet's NAT gateway (for outbound allowlisting), or empty when NAT is off."
  value       = var.runner_nat_enabled ? azurerm_public_ip.runner_nat[0].ip_address : ""
}

output "pg_private_dns_zone_id" {
  description = "Private DNS zone id for PG Flexible Server, or empty when no zone was created."
  value       = var.pg_private_dns_zone_name == "" ? "" : azurerm_private_dns_zone.pg[0].id
}

output "blob_private_dns_zone_id" {
  description = "Privatelink DNS zone id for Blob, or empty when private endpoints are off."
  value       = var.private_endpoints_enabled ? azurerm_private_dns_zone.pe["blob"].id : ""
}

output "vault_private_dns_zone_id" {
  description = "Privatelink DNS zone id for Key Vault, or empty when private endpoints are off."
  value       = var.private_endpoints_enabled ? azurerm_private_dns_zone.pe["vault"].id : ""
}

output "redis_private_dns_zone_id" {
  description = "Privatelink DNS zone id for Azure Managed Redis, or empty when the Redis endpoint is off."
  value       = var.redis_private_endpoint_enabled ? azurerm_private_dns_zone.pe["redis"].id : ""
}

output "foundry_private_dns_zone_ids" {
  description = "Privatelink DNS zone ids for AI Foundry / Azure OpenAI, or [] when the Foundry endpoint is off."
  value       = var.foundry_private_endpoint_enabled ? [for k in ["openai", "cognitive", "aiservices"] : azurerm_private_dns_zone.pe[k].id] : []
}
