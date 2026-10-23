# The inputs examples/azure/split/infra and split-public/infra need from the
# cluster owner. For split-public, also look up the cluster's outbound
# addresses (README.md) for workload_egress_ip_ranges.

output "existing_aks_cluster_id" {
  description = "existing_aks_cluster_id for examples/azure/split/infra."
  value       = module.aks.cluster_id
}

output "existing_network" {
  description = "existing_network for the infra folder: the AKS subnet and the proxy address, in the subnet or a static public IP on the public path."
  value = {
    aks_subnet_id = azurerm_subnet.aks.id
    proxy_ip      = local.proxy_ip
  }
}
