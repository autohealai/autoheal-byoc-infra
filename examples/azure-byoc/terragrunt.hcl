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
# once (or have the install guide create it) and fill the values in. Terragrunt feeds
# these to the composition's partial `backend "azurerm"` block at init.
remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-autoheal-tfstate"      # EDIT: state RG
    storage_account_name = "stautohealtfstate"        # EDIT: state storage account (globally unique)
    container_name       = "tfstate"
    key                  = "azure-byoc/terraform.tfstate"
  }
}

inputs = {
  # Identity / naming (environment = lifecycle, not region)
  namespace   = "avid"       # EDIT: customer / tenant
  environment = "play"       # EDIT: stage | prod | play
  name        = "autoheal"

  # Placement
  subscription_id = "00000000-0000-0000-0000-000000000000" # EDIT
  location        = "centralus"                            # EDIT

  # Optional knobs (defaults are sensible; uncomment to change)
  # address_space             = ["10.60.0.0/16"]
  # private_endpoints_enabled = false
  # postgres_sku_name         = "GP_Standard_D2ds_v5"
  # node_vm_size              = "Standard_D4s_v6"
  # node_min_count            = 2
  # node_max_count            = 4
  # acr_sku                   = "Standard"

  # Set to match the Autoheal app install's Kubernetes service accounts.
  # federated_service_accounts = [
  #   { namespace = "app", service_account = "autoheal-app" },
  # ]
}
