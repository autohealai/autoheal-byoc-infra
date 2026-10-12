# Copyable starting config for an Azure / AKS BYOC CONNECT install — the customer
# already built the infrastructure and Autoheal connects the app to it.
#
#   cp -r examples/azure-byoc-connect examples/azure-byoc-connect-mine
#   cd examples/azure-byoc-connect-mine
#   # edit the inputs + remote_state below with the customer's existing resource names
#   terragrunt init && terragrunt plan && terragrunt apply
#   terragrunt output -json > autoheal-infra-outputs.json
#
# See docs/getting-started.md.

terraform {
  # Pin a release when consuming across repos; here we point at the composition in
  # this checkout.
  source = "${get_repo_root()}//compositions/azure-byoc-connect"
}

remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-autoheal-tfstate"      # EDIT: state RG
    storage_account_name = "stautohealtfstate"        # EDIT: state storage account (globally unique)
    container_name       = "tfstate"
    key                  = "azure-byoc-connect/terraform.tfstate"
  }
}

inputs = {
  # Placement
  subscription_id     = "00000000-0000-0000-0000-000000000000" # EDIT
  location            = "centralus"                            # EDIT
  resource_group_name = "rg-customer-autoheal"                 # EDIT: existing RG

  # Existing resources (the customer's names)
  aks_cluster_name     = "aks-customer-autoheal"     # EDIT
  postgres_server_name = "pg-customer-autoheal"      # EDIT
  key_vault_name       = "kv-customer-autoheal"      # EDIT
  redis_cache_name     = "redis-customer-autoheal"   # EDIT
  acr_name             = "crcustomerautoheal"        # EDIT
  storage_account_name = "stcustomerautoheal"        # EDIT
  # storage_container_name = "attachments"

  # App identity this composition creates (Autoheal's own labels)
  namespace   = "nomura"   # EDIT
  environment = "prod"     # EDIT: stage | prod | play
  name        = "autoheal"

  # Match the Autoheal app install's Kubernetes service accounts.
  # federated_service_accounts = [
  #   { namespace = "app", service_account = "autoheal-app" },
  # ]

  # Secret seeding (needs the deployer to hold Key Vault Secrets Officer). The PG
  # password is not readable from the server — pass it here.
  # seed_secrets_enabled = true
  # additional_secrets = {
  #   "postgres-password" = "CHANGE_ME" # pragma: allowlist secret
  # }
}
