# Remote state backend. Configured at init time (partial configuration) by the
# Terragrunt root.hcl in examples/azure, so the storage account, container and key
# are not hard-coded here. State never lives on a laptop for a real install
# (docs/MODULE_STANDARD.md section 11).
terraform {
  backend "azurerm" {}
}
