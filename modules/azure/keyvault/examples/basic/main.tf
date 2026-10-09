# Minimal Key Vault (RBAC mode) with no seed secrets. Doubles as the CI
# plan/validate fixture. tenant_id / deployer_object_id are placeholders.

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

module "keyvault" {
  source = "../../"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  tenant_id          = "00000000-0000-0000-0000-000000000000"
  deployer_object_id = "11111111-1111-1111-1111-111111111111"
}

output "vault_uri" {
  value = module.keyvault.vault_uri
}
