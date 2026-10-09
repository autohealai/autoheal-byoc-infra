# Minimal Flexible Server wired to a vnet module's delegated subnet + PG private
# DNS zone. Doubles as the CI plan/validate fixture.
#
# attributes = ["db"] gives the server a distinct name (avid-play-autoheal-db)
# from the other components sharing the same namespace/environment/name.

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

  namespace                = "avid"
  environment              = "play"
  name                     = "autoheal"
  resource_group_name      = "rg-autoheal-play"
  location                 = "centralus"
  pg_private_dns_zone_name = "avid-play.private.postgres.database.azure.com"
}

module "postgres" {
  source = "../../"

  # null-label (environment = lifecycle, not region); "db" distinguishes the name
  namespace   = "avid"
  environment = "play"
  name        = "autoheal"
  attributes  = ["db"]

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  delegated_subnet_id = module.vnet.subnet_db_id
  private_dns_zone_id = module.vnet.pg_private_dns_zone_id

  # The composition generates this and seeds Key Vault; placeholder for the fixture.
  administrator_password = "REPLACE_ME_IN_composition" # pragma: allowlist secret
}

output "postgres_host" {
  value = module.postgres.host
}

output "postgres_server_id" {
  value = module.postgres.server_id
}
