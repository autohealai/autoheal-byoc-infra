output "id" {
  description = "Resource ID of the cache."
  value       = azurerm_managed_redis.this.id
}

output "name" {
  description = "Name of the cache."
  value       = azurerm_managed_redis.this.name
}

output "hostname" {
  description = "Host clients connect to, <name>.<region>.redis.azure.net."
  value       = azurerm_managed_redis.this.hostname
}

output "port" {
  description = "TLS port of the default database (10000)."
  value       = try(azurerm_managed_redis.this.default_database[0].port, 10000)
}

output "primary_access_key" {
  description = "Primary access key of the default database."
  value       = try(azurerm_managed_redis.this.default_database[0].primary_access_key, "")
  sensitive   = true
}
