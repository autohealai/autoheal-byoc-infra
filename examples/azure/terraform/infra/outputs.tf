# The composition's outputs, passed on. The app folder reads autoheal_values and
# cluster from this folder's state.

output "autoheal_values" {
  value       = module.infra.autoheal_values
  description = "The chart's infra values. The app folder passes them to the chart."
}

output "autoheal_values_yaml" {
  value       = module.infra.autoheal_values_yaml
  description = "The same values as YAML, for a Helm or Flux install."
}

output "cluster" {
  value       = module.infra.cluster
  description = "The cluster name, resource group, API endpoint and CA certificate."
}

output "required_role_assignments" {
  value       = module.infra.required_role_assignments
  description = "Grants your administrators must make. Empty when Terraform makes them."
}

output "required_dns_records" {
  value       = module.infra.required_dns_records
  description = "DNS records a person must create. Empty when Terraform creates them."
}

output "required_cluster_owner_actions" {
  value       = module.infra.required_cluster_owner_actions
  description = "What the cluster owner does when you bring the cluster. Empty otherwise."
}

output "network" {
  value       = module.infra.network
  description = "The VNet and subnet IDs and the address space."
}
