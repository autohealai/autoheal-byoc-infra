# Private endpoint for a Blob account, wired to the vnet module's PE subnet and
# privatelink DNS zone. Doubles as the CI plan/validate fixture.

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

  namespace                 = "avid"
  environment               = "play"
  name                      = "autoheal"
  resource_group_name       = "rg-autoheal-play"
  location                  = "centralus"
  private_endpoints_enabled = true
}

module "blob" {
  source = "../../../blob"

  namespace           = "avid"
  environment         = "play"
  name                = "autoheal"
  resource_group_name = "rg-autoheal-play"
  location            = "centralus"
}

module "pe_blob" {
  source = "../../"

  # attributes distinguishes this endpoint's name from vault/foundry endpoints
  namespace   = "avid"
  environment = "play"
  name        = "autoheal"
  attributes  = ["blob"]

  resource_group_name  = "rg-autoheal-play"
  location             = "centralus"
  subnet_id            = module.vnet.subnet_pe_id
  target_resource_id   = module.blob.account_id
  subresource_names    = ["blob"]
  private_dns_zone_ids = [module.vnet.blob_private_dns_zone_id]
}

output "pe_private_ip" {
  value = module.pe_blob.private_ip_address
}
