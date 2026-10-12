# User-assigned identity + a federated credential for one service account. Role
# assignments are disabled here so the fixture needs no real Key Vault / Blob / ACR;
# a composition wires key_vault_id / storage_account_id / acr_id from those modules.
# Doubles as the CI plan/validate fixture.

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "workload_identity" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  oidc_issuer_url = "https://centralus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/"
  federated_service_accounts = [
    { namespace = "app", service_account = "autoheal-app" },
  ]

  kv_role_enabled   = false
  blob_role_enabled = false
}

output "client_id" {
  value = module.workload_identity.client_id
}
