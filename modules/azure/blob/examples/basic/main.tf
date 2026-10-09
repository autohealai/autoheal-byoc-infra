# Minimal Blob storage account + container. Doubles as the CI plan/validate fixture.

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

module "blob" {
  source = "../../"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"
}

output "account_name" {
  value = module.blob.account_name
}

output "blob_endpoint" {
  value = module.blob.blob_endpoint
}
