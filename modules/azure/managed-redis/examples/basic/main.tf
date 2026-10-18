# Azure Managed Redis with test-subscription defaults. Doubles as the CI validate
# fixture.

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

module "managed_redis" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"
}

output "hostname" {
  value = module.managed_redis.hostname
}
