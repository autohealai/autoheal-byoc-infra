output "id" {
  description = "Resource ID of the private endpoint."
  value       = azurerm_private_endpoint.this.id
}

output "private_ip_address" {
  description = "Private VNet IP assigned to the PE NIC."
  value       = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}
