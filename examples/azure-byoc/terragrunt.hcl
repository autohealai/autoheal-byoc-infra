# Copyable starting config for an Azure / AKS BYOC install.
#
#   cp -r examples/azure-byoc examples/azure-byoc-mine
#   cd examples/azure-byoc-mine
#   # edit the inputs + remote_state below
#   terragrunt init && terragrunt plan && terragrunt apply
#   terragrunt output -json > autoheal-infra-outputs.json
#
# See docs/CONSUMING.md.

terraform {
  # Pin a release when consuming across repos; here we point at the composition in
  # this checkout.
  source = "${get_repo_root()}//compositions/azure-byoc"
}

# Remote state: one storage account/container holds this install's state. Create it
# ONCE with scripts/bootstrap-state-azure.sh (Terraform cannot create the account
# that stores its own state), then put the matching names here. Terragrunt feeds
# these to the composition's partial `backend "azurerm"` block at init.
remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-autoheal-tfstate" # EDIT: state RG (bootstrap arg)
    storage_account_name = "stautohealtfstate"   # EDIT: state storage account, 3-24 lowercase alnum, globally unique (bootstrap arg)
    container_name       = "tfstate"
    key                  = "azure-byoc/terraform.tfstate"
  }
}

inputs = {
  # Identity / naming (environment = lifecycle, not region)
  namespace   = "REPLACE_ME" # EDIT: customer / tenant short name, e.g. "avid"
  environment = "play"       # EDIT: stage | prod | play
  name        = "autoheal"

  # Placement
  subscription_id = "REPLACE_ME" # EDIT: az account show --query id -o tsv
  location        = "centralus"  # EDIT: PG Flexible region (centralus | westus3 | northcentralus)

  # Optional knobs (defaults are sensible; uncomment to change)
  # address_space             = ["10.60.0.0/16"]
  # private_endpoints_enabled = false
  # postgres_sku_name         = "GP_Standard_D2ds_v5"
  # node_vm_size              = "Standard_D4s_v6"
  # node_min_count            = 2
  # node_max_count            = 4
  # acr_sku                   = "Standard"

  # App-identity federation. The default already matches the autoheal-byoc chart
  # (api-server-go, agents-py-http, agents-py-worker in namespace "autoheal").
  # Only override if you install the app into a different namespace or SA names.
  # federated_service_accounts = [
  #   { namespace = "autoheal", service_account = "api-server-go" },
  #   { namespace = "autoheal", service_account = "agents-py-http" },
  #   { namespace = "autoheal", service_account = "agents-py-worker" },
  # ]
}
