output "vmss_id" {
  description = "Resource ID of the Temporal scale set (one VM)."
  value       = azurerm_linux_virtual_machine_scale_set.temporal.id
}

output "vmss_name" {
  description = "Name of the Temporal scale set, for az vmss run-command and az vmss reimage."
  value       = azurerm_linux_virtual_machine_scale_set.temporal.name
}

output "public_ip" {
  description = "Static public IP of the load balancer. Clients dial <public_ip>:7233, and the VM's outbound traffic leaves from it."
  value       = azurerm_public_ip.temporal.ip_address
}

output "load_balancer_id" {
  description = "Resource ID of the load balancer in front of the VM."
  value       = azurerm_lb.temporal.id
}

output "identity_id" {
  description = "Resource ID of the VM's user-assigned identity."
  value       = azurerm_user_assigned_identity.temporal.id
}

output "identity_principal_id" {
  description = "Principal ID of the VM's user-assigned identity. Grant it Key Vault Secrets User on each key entry and the certificate entry."
  value       = azurerm_user_assigned_identity.temporal.principal_id
}

output "identity_client_id" {
  description = "Client ID of the VM's user-assigned identity."
  value       = azurerm_user_assigned_identity.temporal.client_id
}

output "vnet_id" {
  description = "Resource ID of the VM's VNet."
  value       = azurerm_virtual_network.temporal.id
}

output "network_security_group_id" {
  description = "Resource ID of the NSG on snet-temporal."
  value       = azurerm_network_security_group.temporal.id
}

output "data_collection_rule_id" {
  description = "Resource ID of the data collection rule that sends the VM's logs to the workspace. Null without log_analytics_workspace_id."
  value       = local.logs_enabled ? azurerm_monitor_data_collection_rule.temporal[0].id : null
}

output "health_alert_id" {
  description = "Resource ID of the metric alert on the load balancer's health probe."
  value       = azurerm_monitor_metric_alert.health.id
}
