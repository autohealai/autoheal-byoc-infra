# Secrets identity: user-assigned identity, a federated credential per chart
# ServiceAccount, and Key Vault Secrets User on the install's vault. The
# key_vault_id below is a placeholder scope string (a composition wires the real
# one); plan does not check that it exists. Doubles as the CI validate fixture.

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

module "secrets_identity" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["secrets"]

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  oidc_issuer_url = "https://centralus.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/"
  key_vault_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-autoheal-play/providers/Microsoft.KeyVault/vaults/kvautohealplay"

  service_accounts = [
    { namespace = "autoheal", service_account = "api-server-go" },
    { namespace = "autoheal", service_account = "agents-py-worker" },
  ]
}

output "client_id" {
  value = module.secrets_identity.client_id
}
