# Outputs for the network owner and for people.
#
#   egress_ip                       the NAT gateway's public IP, null with
#                                   existing_subnet_id
#   subnet_id, subnet_cidr          the runner subnet, created or brought
#   identity_principal_id,
#   identity_client_id              the runner VMs' user-assigned identity
#   vmss_id                         the runner VM scale set
#   required_network_owner_actions  what the network owner must open
#   required_role_assignments       grants an administrator must make, filled
#                                   only when create_role_assignments = false
#
# None of them holds a secret. The generated SSH private key and temporal_token
# stay in the state.

locals {
  # The ports the runner dials on the Temporal address: Temporal, and the
  # tool-result listener when it is on the same host.
  temporal_ports = distinct(compact([
    local.temporal_port,
    local.tool_response_host == local.temporal_host ? local.tool_response_port : "",
  ]))

  temporal_purpose = var.temporal_tls ? "Temporal through the edge" : (
    local.tool_response_host == local.temporal_host ? "Temporal and sandbox tool results" : "Temporal"
  )

  network_owner_actions = concat(
    local.create_network ? [
      var.temporal_tls ?
      "Give the runner VNet ${local.id}-runner (${var.address_space}, resource group ${local.resource_group_name}) a route to ${local.temporal_host}: connect it privately to the edge's network, through your hub or a VNet peering, or let it reach a public edge through its NAT gateway." :
      "Connect the runner VNet ${local.id}-runner (${var.address_space}, resource group ${local.resource_group_name}) privately to the cluster's VNet, through your hub or a VNet peering. Do not publish Temporal on the internet: it has no login, and the traffic carries git tokens and command output.",
    ] : [],
    [
      "Allow the runner subnet ${local.subnet_cidr}${local.create_network && var.temporal_tls ? ", or its NAT gateway's IP over the internet (the egress_ip output)," : ""} to ${local.temporal_host} on TCP ${join(" and ", local.temporal_ports)} (${local.temporal_purpose}).",
    ],
    var.temporal_tls ? [
      "Point ${local.temporal_host} at the edge like the app hostnames: it is the chart's global.edge.runner.host. The edge certificate must cover it, and a shared Istio Gateway must list it in its hosts.",
    ] : [],
    local.tool_response_host != "" && local.tool_response_host != local.temporal_host ? [
      "Allow the runner subnet ${local.subnet_cidr} to ${local.tool_response_host} on TCP ${local.tool_response_port} (sandbox tool results).",
    ] : [],
    local.create_network ? [] : [
      "The runner subnet ${split("/", var.existing_subnet_id)[10]} uses your routes and no NAT gateway is created: it needs a route to ${local.temporal_host} and outbound access to the image registry (${split("/", var.runner_image)[0]}), the git hosts and the endpoints the tools call.",
    ],
  )
}

output "egress_ip" {
  description = "Public IP the runner VMs' outbound traffic leaves from (the NAT gateway), for allow lists on git hosts and tool endpoints. Null with existing_subnet_id, where your routes decide."
  value       = local.egress_ip
}

output "subnet_id" {
  description = "Resource ID of the runner subnet: snet-runner in the VNet we create, or existing_subnet_id."
  value       = local.subnet_id
}

output "subnet_cidr" {
  description = "Address range of the runner subnet, the source of the network rule."
  value       = local.subnet_cidr
}

output "identity_principal_id" {
  description = "Principal ID of the runner VMs' user-assigned identity (granted AcrPull on acr_id)."
  value       = module.runner.identity_principal_id
}

output "identity_client_id" {
  description = "Client ID of the runner VMs' user-assigned identity."
  value       = module.runner.identity_client_id
}

output "vmss_id" {
  description = "Resource ID of the runner VM scale set."
  value       = module.runner.vmss_id
}

output "required_network_owner_actions" {
  description = "What the network owner must do, as readable lines: give the runner a route to temporal_address and allow it there, and, through the edge, point the runner host at the edge. With existing_subnet_id, also the outbound access the subnet needs."
  value       = local.network_owner_actions
}

output "required_role_assignments" {
  description = "Role grants an administrator must make, as readable lines. Filled only when create_role_assignments = false and acr_id is set."
  value       = local.required_role_assignments
}
