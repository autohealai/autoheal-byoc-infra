# The cloud resources, for an AKS cluster in one subscription (the cluster
# subscription) with everything else in another (the data subscription), and no
# network connection between them. Pods reach the data services over their
# public endpoints, which let in only the cluster's addresses. The runner VMs
# reach Temporal on a static public IP in the cluster subscription, which lets
# in only the runner's address. In the cluster subscription we only read the
# cluster and its AKS subnet; we create nothing there. See
# docs/azure-two-subscriptions-public.md in autoheal-byoc-infra, and
# docs/azure-two-subscriptions-public-runbook.md for every command.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

# Our code, pinned to the tag in versions.hcl.
terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure?ref=v${local.v.infra_version}"
}

inputs = {
  namespace        = "acme"
  environment      = "prod"
  location         = "eastus2"             # the cluster's region
  autoheal_version = local.v.chart_version # the runner VMs pull app/runner-go:chart-<chart_version>

  # The data subscription. Everything Terraform creates goes here.
  subscription_id = "11111111-2222-3333-4444-555555555555"

  # The cluster, in the cluster subscription. We only read it.
  existing_aks_cluster_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-cop/providers/Microsoft.ContainerService/managedClusters/aks-cop"

  # The Kubernetes namespace the cluster owner gives you. The workload
  # identities trust the service accounts in it only. Keep it the same as
  # namespace in ../app/terragrunt.hcl.
  service_accounts = { namespace = "autoheal" }

  # Public endpoints instead of a VNet connection.
  cluster_network_path = "public"

  existing_network = {
    # The AKS subnet of that cluster.
    aks_subnet_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
    # A Standard static public IP the cluster owner creates in the cluster's
    # node resource group. The runner VMs connect here.
    temporal_ip = "20.30.40.50"
    # A free address in snet-aks for the proxy. Users on your network connect
    # here; DNS points here.
    proxy_ip = "10.40.15.252"
  }

  # The cluster's fixed public outbound addresses. Postgres and the Key Vaults
  # let in only these.
  workload_egress_ip_ranges = ["198.51.100.20/32"]

  # The public addresses of the host that runs this apply. The Key Vaults and
  # storage let them in, so the apply can write the vault entries.
  deployer_ip_ranges = ["203.0.113.10/32"]

  # Address range of the VNet we create in the data subscription for the runner
  # VMs. It is never connected to the cluster's VNet.
  network_cidr = "10.70.0.0/16"

  # The DNS zone for the hostnames, in the data subscription. If the zone is in
  # another subscription or outside Azure DNS, remove this line and set
  # create_dns_records = false; the required_dns_records output then lists the
  # records for your DNS team.
  existing_dns_zone_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"

  # The name users open in a browser. Login is at auth.autoheal.acme.example and
  # auth-app at auth-app.autoheal.acme.example.
  hostname  = "autoheal.acme.example"
  edge_mode = "loadbalancer"

  # Sizing
  postgres_sku      = "GP_Standard_D4ds_v5"
  runner_node_count = 2

  # The LLM API key is a secret, so it is not in this file. The pipeline passes
  # it as TF_VAR_llm_api_key and Terraform stores it in Key Vault as llm-api-key.
}
