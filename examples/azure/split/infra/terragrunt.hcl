# The cloud resources, for an AKS cluster in one subscription (the cluster
# subscription) with everything else in another (the data subscription). In
# the cluster subscription we only read the cluster and its AKS subnet; we
# create nothing there. In the data subscription we create a VNet for the
# runner VMs, Postgres and the private endpoints, and Postgres, Redis, storage,
# both Key Vaults, the workload identities, the runner VMs and the DNS records.
# See docs/azure-two-subscriptions.md in autoheal-byoc-infra.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

# Our code, pinned to the tag in versions.hcl.
terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure?ref=v${local.v.infra_version}"
}

inputs = {
  namespace        = "acme"
  environment      = "prod"
  location         = "eastus2"
  autoheal_version = local.v.chart_version # the runner VMs pull app/runner-go:chart-<chart_version>

  # The data subscription. Everything Terraform creates goes here.
  subscription_id = "11111111-2222-3333-4444-555555555555"

  # The cluster, in the cluster subscription. We only read it.
  existing_aks_cluster_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-cop/providers/Microsoft.ContainerService/managedClusters/aks-cop"

  # The Kubernetes namespace the cluster owner gives you. The workload
  # identities trust the service accounts in it only. Keep it the same as
  # namespace in ../app/terragrunt.hcl.
  service_accounts = { namespace = "autoheal" }

  # The AKS subnet of that cluster, and two free addresses in it. The cluster
  # owner picks them. The chart pins its Temporal and proxy internal load
  # balancers to them.
  existing_network = {
    aks_subnet_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
    temporal_ip   = "10.40.15.253" # the runner VMs connect here
    proxy_ip      = "10.40.15.252" # users connect here; DNS points here
  }

  # Address range of the VNet we create in the data subscription for the
  # runner VMs, Postgres and the private endpoints. It must not overlap vnet-cop,
  # because the two VNets are peered.
  network_cidr = "10.70.0.0/16"

  # Link the private DNS zones we create to vnet-cop, so pods find Postgres,
  # Redis, storage and the vaults. Needs the join permission on vnet-cop (see the
  # required_cluster_owner_actions output). Set false when your own DNS resolves
  # these zones for vnet-cop.
  cluster_vnet_dns_link_enabled = true

  # The DNS zone for the hostnames, in the data subscription. If the zone is
  # in another subscription or outside Azure DNS, remove this line and set
  # create_dns_records = false; the required_dns_records output then lists the
  # records for your DNS team.
  existing_dns_zone_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"

  # The name users open in a browser. Login is at auth.autoheal.acme.example and
  # auth-app at auth-app.autoheal.acme.example.
  hostname  = "autoheal.acme.example"
  edge_mode = "loadbalancer"

  # Pods reach storage and the vaults through private endpoints; the apply host
  # writes the vault entries from its public egress address.
  private_endpoints_enabled = true
  deployer_ip_ranges        = ["203.0.113.10/32"]

  # Sizing
  postgres_sku      = "GP_Standard_D4ds_v5"
  runner_node_count = 2

  # The LLM API key is a secret, so it is not in this file. The pipeline passes
  # it as TF_VAR_llm_api_key and Terraform stores it in Key Vault as llm-api-key.
}
