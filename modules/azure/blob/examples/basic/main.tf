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

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  # This is an init/validate/plan fixture. The module keeps the firewall at its secure
  # Deny default, so `terraform apply` from an arbitrary host would 403 on container
  # creation (a data-plane call). To make it appliable, give the apply host a path to the
  # account — either reach it over a private endpoint, or allow-list the host's public IP
  # without weakening the default:
  #   allowed_ip_ranges = ["203.0.113.10/32"] # replace with your apply host's IP/CIDR
}

output "account_name" {
  value = module.blob.account_name
}

output "blob_endpoint" {
  value = module.blob.blob_endpoint
}
