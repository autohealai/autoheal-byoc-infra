# Written once. Every folder below includes it, so each folder gets its own
# state file in the same storage account: autoheal/prod/infra,
# autoheal/prod/app, and so on.
#
# Create the storage account once, before the first run, with
# scripts/bootstrap-state-azure.sh from autoheal-byoc-infra. Terraform cannot
# create the account that holds its own state.
#
# generate writes backend.tf into each folder's working copy of the
# composition. The compositions ship without a backend.tf for this reason.

remote_state {
  backend = "azurerm"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    resource_group_name  = "rg-acme-tfstate"
    storage_account_name = "stacmetfstate"
    container_name       = "tfstate"
    key                  = "autoheal/${path_relative_to_include()}/terraform.tfstate"
    use_azuread_auth     = true
  }
}
