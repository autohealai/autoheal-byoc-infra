# AKS cluster wired to a vnet (node subnet + Network Contributor scope). Doubles as
# the CI plan/validate fixture.

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

module "aks" {
  source = "../../"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  vnet_id        = module.vnet.vnet_id
  vnet_subnet_id = module.vnet.subnet_aks_id

  # No ACR in this fixture; skip the kubelet AcrPull grant.
  acr_pull_enabled = false
}

output "cluster_name" {
  value = module.aks.cluster_name
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}
