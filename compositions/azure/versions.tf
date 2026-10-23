terraform {
  # 1.7 for removed blocks (moved.tf, modules/azure/keyvault).
  required_version = ">= 1.7"

  # Provider pins only. The chart is installed by compositions/app, so this
  # composition has no helm or kubernetes provider.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
