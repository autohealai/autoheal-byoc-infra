# The cloud resources: network, AKS, Postgres, Redis, storage, Key Vault,
# workload identities, the runner VMs and the DNS records. The same inputs as
# ../../prod/infra/terragrunt.hcl, which explains each one.

module "infra" {
  # Our code, pinned to a release. To upgrade, change the tag here and in
  # ../app/main.tf.
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure?ref=v3.0.0"

  namespace        = "acme"
  environment      = "prod"
  subscription_id  = "11111111-2222-3333-4444-555555555555"
  location         = "eastus2"
  autoheal_version = var.autoheal_version

  existing_dns_zone_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"
  network_cidr         = "10.60.0.0/16"

  # Things you already have go here as existing_* inputs. For an AKS cluster
  # someone else runs, copy the inputs from ../../split/infra/terragrunt.hcl and
  # set create_namespace = false in ../app/main.tf.

  aks_node_size     = "Standard_D8s_v5"
  aks_node_count    = 3
  postgres_sku      = "GP_Standard_D4ds_v5"
  runner_node_count = 2

  hostname  = "autoheal.acme.example"
  edge_mode = "loadbalancer"

  # The pipeline agents' outbound address: Terraform writes the vault entries
  # through the vault's firewall.
  private_endpoints_enabled = true
  deployer_ip_ranges        = ["203.0.113.10/32"]

  llm_api_key = var.llm_api_key
}
