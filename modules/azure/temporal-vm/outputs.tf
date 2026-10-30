output "vm_id" {
  description = "Resource ID of the Temporal VM."
  value       = azurerm_linux_virtual_machine.temporal.id
}

output "vm_name" {
  description = "Name of the Temporal VM, for az vm run-command and az vm boot-diagnostics."
  value       = azurerm_linux_virtual_machine.temporal.name
}

output "public_ip" {
  description = "Static public IP of the VM. Clients dial <public_ip>:7233; it stays when the VM is replaced."
  value       = azurerm_public_ip.temporal.ip_address
}

output "vnet_id" {
  description = "Resource ID of the VM's VNet."
  value       = azurerm_virtual_network.temporal.id
}

output "network_security_group_id" {
  description = "Resource ID of the NSG on snet-temporal."
  value       = azurerm_network_security_group.temporal.id
}
