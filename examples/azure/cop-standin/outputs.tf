# The inputs examples/azure/split/infra and split-public/infra need from the
# cluster owner. For split-public, also look up the cluster's outbound
# addresses (README.md) for workload_egress_ip_ranges.

output "existing_aks_cluster_id" {
  description = "existing_aks_cluster_id for examples/azure/split/infra."
  value       = module.aks.cluster_id
}

output "existing_network" {
  description = "existing_network for the infra folder: the AKS subnet, and the proxy and Temporal addresses: in the subnet, or static public IPs on the public path."
  value = {
    aks_subnet_id = azurerm_subnet.aks.id
    temporal_ip   = local.temporal_ip
    proxy_ip      = local.proxy_ip
  }
}
