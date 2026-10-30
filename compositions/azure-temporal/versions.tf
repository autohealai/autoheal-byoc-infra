terraform {
  required_version = ">= 1.7"

  # Provider pins only. The VM's clients are configured elsewhere, so this
  # composition has no helm or kubernetes provider.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.50"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
