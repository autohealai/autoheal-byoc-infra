# Generic Azure Private Endpoint — the AWS analogue is a VPC interface endpoint.
# Projects a PaaS resource (Blob account, Key Vault, AI Foundry account) into the
# private-endpoint subnet as a NIC with a private VNet IP, and binds that IP into
# the supplied privatelink DNS zones so in-VNet clients (AKS pods via the
# VNet-linked zones from modules/azure/vnet) resolve the resource privately.
#
# This module adds only the private PATH; it does NOT disable the resource's
# public network access. Flipping a resource to private-only is coordinated
# separately, because the Terraform deployer typically runs outside the VNet and
# would lose the data-plane access it needs on first apply (seed secrets, create
# containers).
#
# Generic by design: instantiate once per target, using attributes to give each a
# distinct name (attributes = ["blob"] / ["vault"] / ["foundry"]).

resource "azurerm_private_endpoint" "this" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${module.this.id}-psc"
    private_connection_resource_id = var.target_resource_id
    subresource_names              = var.subresource_names
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = var.private_dns_zone_ids
  }

  tags = module.this.tags
}
