# Outputs for the app folder and for people. The AWS composition emits the same
# names in 2.x (docs/MODULE_STANDARD.md section 8).
#
#   autoheal_values            the chart's infra values, as an object
#   autoheal_values_yaml       the same values as YAML text (values-infra.yaml)
#   cluster                    what compositions/app needs to log in to the cluster
#   required_role_assignments  grants an administrator must make, filled only when
#                              create_role_assignments = false
#   required_dns_records       records a person must create, filled only when we
#                              do not create them
#   network                    the VNet and subnets Autoheal runs in, created or
#                              brought
#
# None of them holds a secret.

output "autoheal_values" {
  description = "Infra values for the Autoheal chart (global.infra facts, suggestions, and the Temporal and Zitadel copies). Pass to compositions/app as infra_values."
  value       = local.autoheal_values
}

output "autoheal_values_yaml" {
  description = "autoheal_values as YAML, for customers who install with Helm or Flux and commit values-infra.yaml."
  value       = yamlencode(local.autoheal_values)
}

output "cluster" {
  description = "Cluster connection details for compositions/app: cloud, name, resource_group, endpoint and base64 ca_certificate. Authentication is kubelogin with Entra ID; no credential is output."
  value = {
    cloud          = "azure"
    name           = local.cluster_name
    resource_group = local.cluster_rg
    endpoint       = local.cluster_endpoint
    ca_certificate = local.cluster_ca_certificate
  }
}

output "required_role_assignments" {
  description = "Role grants an administrator must make, as readable lines. Filled only when create_role_assignments = false; the apply stops while a workload grant is missing."
  value = var.create_role_assignments ? [] : [
    for k in local.required_grant_order : local.required_grants[k].text if contains(keys(local.required_grants), k)
  ]
}

output "required_dns_records" {
  description = "DNS records a person must create (name, type, value). Filled when create_dns_records = false, or when the address is not known yet (edge_address empty in a mode other than loadbalancer)."
  value       = local.required_dns_records
}

output "network" {
  description = "The VNet and subnets Autoheal runs in: vnet_id, vnet_name, resource_group_name, address_space, aks_subnet_id, runner_subnet_id and private_endpoint_subnet_id. For a brought network the VNet is not read, so address_space is empty, and private_endpoint_subnet_id is empty when existing_network.endpoint_subnet_id is."
  value = {
    vnet_id                    = local.create_network ? module.vnet[0].vnet_id : local.brought_vnet_id
    vnet_name                  = local.create_network ? module.vnet[0].vnet_name : try(split("/", local.brought_vnet_id)[8], "")
    resource_group_name        = local.create_network ? local.rg : try(split("/", local.brought_vnet_id)[4], "")
    address_space              = local.create_network ? [var.network_cidr] : []
    aks_subnet_id              = local.aks_subnet_id
    runner_subnet_id           = local.runner_subnet_id
    private_endpoint_subnet_id = local.endpoint_subnet_id
  }
}
