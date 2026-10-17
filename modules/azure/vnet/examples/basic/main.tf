# Minimal VNet: the default four subnets + runner NAT, no private endpoints, and
# the AKS subnet NSG for the reserved Temporal address. Doubles as the CI
# plan/validate fixture.

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

  # Third address from the end of the default AKS subnet 10.60.0.0/20.
  temporal_ip = "10.60.15.253"
}

output "vnet_id" {
  value = module.vnet.vnet_id
}

output "subnet_runner_id" {
  value = module.vnet.subnet_runner_id
}

output "runner_nat_public_ip" {
  value = module.vnet.runner_nat_public_ip
}
