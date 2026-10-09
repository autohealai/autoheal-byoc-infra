output "hostname" {
  description = "Cache hostname (private, resolves to the injected subnet IP)."
  value       = azurerm_redis_cache.this.hostname
}

output "ssl_port" {
  description = "TLS port (non-SSL port is disabled)."
  value       = azurerm_redis_cache.this.ssl_port
}

output "endpoint" {
  description = "host:ssl_port. Maps to the cross-cloud output contract 'redis_endpoint'."
  value       = "${azurerm_redis_cache.this.hostname}:${azurerm_redis_cache.this.ssl_port}"
}

output "primary_access_key" {
  description = "Primary access key. Seed into Key Vault for the app; never a root output in the clear."
  value       = azurerm_redis_cache.this.primary_access_key
  sensitive   = true
}

output "redis_id" {
  description = "Resource ID of the cache."
  value       = azurerm_redis_cache.this.id
}
