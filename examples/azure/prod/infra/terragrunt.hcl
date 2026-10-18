# The cloud resources: network, AKS, Postgres, Redis, storage, Key Vault,
# workload identities, the runner VMs and the DNS records. The source line reads
# the infra tag from versions.hcl, so this file does not change on upgrade.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

# Our code, pinned to the tag in versions.hcl. To try changes from a local
# checkout instead: source = "/path/to/autoheal-byoc-infra//compositions/azure"
terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure?ref=v${local.v.infra_version}"
}

inputs = {
  namespace        = "acme"
  environment      = "prod"
  subscription_id  = "11111111-2222-3333-4444-555555555555"
  location         = "eastus2"
  autoheal_version = local.v.chart_version # the runner VMs pull app/runner-go:chart-1.0.0

  # We never create a DNS zone, only the records in it. If the zone is not in
  # Azure DNS (Cloudflare, Infoblox), remove this line and set
  # create_dns_records = false; the required_dns_records output then lists the
  # records for your DNS team.
  existing_dns_zone_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"

  # With nothing below set, we create everything else, with a new network in
  # this range.
  network_cidr = "10.60.0.0/16"

  # Things you already have. Uncomment the ones you bring; anything not listed,
  # we create. A brought resource is only read, never changed.
  #
  # existing_network = {
  #   aks_subnet_id      = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-aks"
  #   postgres_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pg" # we create Postgres here
  #   endpoint_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pe"
  #   runner_subnet_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-runner"
  #
  #   # Free addresses in snet-aks. Your network team picks them, because we
  #   # cannot tell which addresses in your subnet are in use.
  #   temporal_ip = "10.20.4.11" # the runner VMs connect here
  #   proxy_ip    = "10.20.4.10" # loadbalancer mode only; DNS points here
  # }
  #
  # existing_aks_cluster_id       = "/subscriptions/.../resourceGroups/rg-platform/providers/Microsoft.ContainerService/managedClusters/aks-platform"
  # existing_postgres_id          = "/subscriptions/.../resourceGroups/rg-platform/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-platform"
  # existing_redis_id             = "/subscriptions/.../resourceGroups/rg-platform/providers/Microsoft.Cache/redisEnterprise/redis-platform"
  # existing_storage_account_id   = "/subscriptions/.../resourceGroups/rg-platform/providers/Microsoft.Storage/storageAccounts/stplatform"
  # existing_key_vault_id         = "/subscriptions/.../resourceGroups/rg-platform/providers/Microsoft.KeyVault/vaults/kv-platform"
  # existing_runtime_key_vault_id = "/subscriptions/.../resourceGroups/rg-platform/providers/Microsoft.KeyVault/vaults/kv-platform-rt" # not the vault above
  #
  # With existing_postgres_id, pass the server's admin password as
  # TF_VAR_postgres_admin_password from the pipeline's secret store.

  # Role grants. true: Terraform makes every grant, so the deployer needs Owner,
  # or Contributor plus User Access Administrator. false: an administrator makes
  # the grants listed in the required_role_assignments output, and the apply
  # stops until they exist.
  # create_role_assignments = false

  # Sizing
  aks_node_size     = "Standard_D8s_v5"
  aks_node_count    = 3
  postgres_sku      = "GP_Standard_D4ds_v5"
  runner_node_count = 2

  # The name users open in a browser. Terraform creates its DNS record and passes
  # it to the app. Login is at auth.autoheal.acme.example and auth-app at
  # auth-app.autoheal.acme.example unless auth_hostname or auth_app_hostname is
  # set.
  hostname = "autoheal.acme.example"

  # How traffic reaches the Autoheal proxy. loadbalancer: we reserve an internal
  # address for it and point DNS there. For gateway-api, istio or ingress, set
  # edge_address to the address of that edge instead.
  edge_mode = "loadbalancer"

  # Network paths to the storage account and Key Vault, which deny public access
  # by default. Pods reach them through private endpoints; the apply host writes
  # the vault entries from its public egress address.
  private_endpoints_enabled = true
  deployer_ip_ranges        = ["203.0.113.10/32"]

  # The LLM API key is a secret, so it is not in this file. The pipeline passes
  # it as TF_VAR_llm_api_key and Terraform stores it in Key Vault as llm-api-key.
  # Through an LLM gateway, also TF_VAR_llm_gateway_api_key (any value for a
  # gateway that ignores it, such as Portkey OSS) and, when the gateway needs
  # headers, TF_VAR_llm_gateway_extra_headers.
}
