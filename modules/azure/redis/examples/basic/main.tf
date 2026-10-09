# Minimal Premium Redis injected into a vnet module's dedicated redis subnet.
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

module "vnet" {
  source = "../../../vnet"

  namespace           = "avid"
  environment         = "play"
  name                = "autoheal"
  resource_group_name = "rg-autoheal-play"
  location            = "centralus"
}

module "redis" {
  source = "../../"

  # null-label (environment = lifecycle, not region)
  namespace   = "avid"
  environment = "play"
  name        = "autoheal"

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  # Premium VNet injection into the vnet module's dedicated redis subnet.
  subnet_id = module.vnet.subnet_redis_id
  capacity  = 1
}

output "redis_endpoint" {
  value = module.redis.endpoint
}
