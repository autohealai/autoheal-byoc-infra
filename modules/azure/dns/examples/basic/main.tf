# Three A records in an existing zone. Doubles as the CI validate fixture.

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

module "dns" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  zone_name                = "autoheal.acme.example"
  zone_resource_group_name = "rg-dns"
  records = {
    "@"        = "10.60.15.254"
    "auth"     = "10.60.15.254"
    "auth-app" = "10.60.15.254"
  }
}

output "fqdns" {
  value = module.dns.fqdns
}
