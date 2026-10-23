# Minimal VNet: the default three subnets, no private endpoints. Doubles as the
# CI plan/validate fixture.

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

module "vnet" {
  source = "../../"

  # null-label (environment = lifecycle, not region)
  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"
}

output "vnet_id" {
  value = module.vnet.vnet_id
}

output "subnet_aks_id" {
  value = module.vnet.subnet_aks_id
}
