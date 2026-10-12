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

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  tenant_id          = "00000000-0000-0000-0000-000000000000"
  deployer_object_id = "11111111-1111-1111-1111-111111111111"

  # This is an init/validate/plan fixture. The module keeps the firewall at its secure
  # Deny default, so `terraform apply` from an arbitrary host would 403 on the data plane
  # (seeding secrets is a data-plane call). To make it appliable, give the apply host a
  # path to the vault — either reach it over a private endpoint, or allow-list the host's
  # public IP without weakening the default:
  #   allowed_ip_ranges = ["203.0.113.10/32"] # replace with your apply host's IP/CIDR
}

output "vault_uri" {
  value = module.keyvault.vault_uri
}
