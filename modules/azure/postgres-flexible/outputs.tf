output "host" {
  description = "Server FQDN (resolves privately via the VNet-linked DNS zone, or publicly with public access). Maps to the cross-cloud output contract 'postgres_host'."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "port" {
  description = "PostgreSQL port."
  value       = 5432
}

output "administrator_login" {
  description = "Server admin username."
  value       = var.administrator_login
}

output "server_id" {
  description = "Resource ID of the Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "name" {
  description = "Server name."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "firewall_rules" {
  description = "Firewall rules of a server with public access, by name: start and end address. Empty for a VNet-integrated server."
  value       = local.firewall_rules
}
