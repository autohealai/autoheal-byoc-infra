# ESO identity: user-assigned identity + federated credential for the ESO
# controller SA + Key Vault Secrets User on the install's Key Vault. The
# key_vault_id below is a placeholder scope string (a composition wires the real
# one from modules/azure/keyvault); plan does not validate that it exists.
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

module "external_secrets" {
  source = "../../"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"
  attributes  = ["eso"]

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  oidc_issuer_url = "https://centralus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/"
  key_vault_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-autoheal-play/providers/Microsoft.KeyVault/vaults/kvautohealplay"
}

output "client_id" {
  value = module.external_secrets.client_id
}

output "service_account" {
  value = module.external_secrets.service_account
}
