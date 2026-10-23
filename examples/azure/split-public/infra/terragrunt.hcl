# The cloud resources, for an AKS cluster in one subscription (the cluster
# subscription) with everything else in another (the data subscription), and no
# network connection between them. Pods reach the data services over their
# public endpoints, which let in only the cluster's addresses. This unit never
# reads or changes anything in the cluster subscription, so it needs no access
# there and the cluster need not exist yet. ../cluster reads the cluster after
# this unit and federates the workload identities to it. See
# docs/azure-two-subscriptions-public.md in autoheal-byoc-infra, and
# docs/azure-two-subscriptions-public-runbook.md for every command.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

# Our code, pinned to the tag in versions.hcl.
terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure?ref=v${local.v.infra_version}"
}

inputs = {
  namespace   = "acme"
  environment = "prod"
  location    = "eastus2" # the cluster's region

  # The data subscription. Everything Terraform creates goes here.
  subscription_id = "11111111-2222-3333-4444-555555555555"

  # The cluster, in the cluster subscription. This unit takes only its name and
  # resource group from the ID; ../cluster reads the cluster itself.
  existing_aks_cluster_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-cop/providers/Microsoft.ContainerService/managedClusters/aks-cop"

  # The Kubernetes namespace the cluster owner gives you. The workload
  # identities trust the service accounts in it only. Keep it the same as
  # namespace in ../app/terragrunt.hcl.
  service_accounts = { namespace = "autoheal" }

  # Public endpoints instead of a VNet connection.
  cluster_network_path = "public"

  existing_network = {
    # The AKS subnet of that cluster. It is never read: the
    # required_cluster_owner_actions output names it in the storage network
    # rule and the NSG rule the cluster owner adds.
    aks_subnet_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
    # A Standard static public IP the cluster owner creates in the cluster's
    # node resource group, for the Autoheal proxy. Users and webhooks connect
    # here; DNS points here.
    proxy_ip = "20.30.40.60"
  }

  # The proxy listens on proxy_ip, open to the internet. For a proxy that only
  # your network reaches, set internal and a free address in snet-aks.
  edge_exposure = "public"

  # The cluster's fixed public outbound addresses. Postgres and the Key Vaults
  # let in only these.
  workload_egress_ip_ranges = ["198.51.100.20/32"]

  # The public addresses of the host that runs this apply. The Key Vaults and
  # storage let them in, so the apply can write the vault entries.
  deployer_ip_ranges = ["203.0.113.10/32"]

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
  postgres_sku = "GP_Standard_D4ds_v5"

  # The LLM API key is a secret, so it is not in this file. The pipeline passes
  # it as TF_VAR_llm_api_key and Terraform stores it in Key Vault as llm-api-key.
}
