# Azure Container Registry for BYOC images. The AWS analogue is modules/aws/ecr.
# There was no Terraform module for this before — registries were created by hand
# today; this codifies it.
#
# admin_enabled stays false: pulls are keyless via managed identity (AcrPull
# granted to the AKS kubelet identity in modules/azure/aks and to the runner
# identity in modules/azure/runner-vmss), so no static registry credentials exist.
#
# Registry names reject dashes and allow 5-50 alphanumeric chars, so we sanitize
# module.this.id; name_override forces an exact name (e.g. crautoheal<env>).

locals {
  registry_name = var.name_override != "" ? var.name_override : substr(lower(replace(module.this.id, "/[^0-9A-Za-z]/", "")), 0, 50)
}

resource "azurerm_container_registry" "this" {
  name                = local.registry_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false

  # Geo-replication is a Premium-only feature; only set when replicas are given.
  dynamic "georeplications" {
    for_each = var.sku == "Premium" ? var.georeplication_locations : []
    content {
      location = georeplications.value
      tags     = module.this.tags
    }
  }

  tags = module.this.tags
}
