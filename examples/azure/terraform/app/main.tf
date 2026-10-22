# Installs the chart. Run it after ../infra has been applied: it reads that
# folder's outputs from its state file.

data "terraform_remote_state" "infra" {
  backend = "azurerm"

  # The same names the pipeline passes to ../infra (pipelines/azure-pipelines.yml).
  config = {
    resource_group_name  = "rg-acme-tfstate"
    storage_account_name = "stacmetfstate"
    container_name       = "tfstate"
    key                  = "autoheal/prod/infra/terraform.tfstate"
    use_azuread_auth     = true
  }
}

module "app" {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/app?ref=v3.0.0"

  chart_version   = var.autoheal_version
  infra_values    = data.terraform_remote_state.infra.outputs.autoheal_values
  cluster         = data.terraform_remote_state.infra.outputs.cluster
  customer_values = file("${path.module}/values-customer.yaml")

  # In Azure DevOps the AzureCLI@2 task signs in first, and kubelogin uses that
  # sign-in.
  kubelogin_login_mode = "azurecli"

  # When the cluster owner created the namespace and gave you rights in it only:
  # create_namespace = false
}
