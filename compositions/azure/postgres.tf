# PostgreSQL Flexible Server: the server we create (private access, VNet
# integrated, private DNS zone linked to the VNet; or public access with a
# firewall on the public path), or the customer's server read through a data
# source.
#
# The admin password of a brought server cannot be read back, so the pipeline
# passes it as TF_VAR_postgres_admin_password. For a server we create it is
# generated unless given. Either way it is stored in the vault as
# postgres-admin-password (secrets.tf) and never output.

# Same arguments as v1, so an upgraded install keeps its password.
resource "random_password" "postgres" {
  count            = local.create_postgres && nonsensitive(var.postgres_admin_password == "") ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%*-_=+"
}

locals {
  postgres_admin_password = nonsensitive(var.postgres_admin_password != "") ? var.postgres_admin_password : try(random_password.postgres[0].result, "")
}

module "postgres" {
  source = "../../modules/azure/postgres-flexible"
  count  = local.create_postgres ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["db"]
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location

  # null rather than "" when the subnet is missing, so the plan stops on the plain
  # message in validation.tf instead of the provider's ID parse error.
  delegated_subnet_id = local.postgres_subnet_id != "" ? local.postgres_subnet_id : null
  private_dns_zone_id = local.postgres_private_dns_zone_id != "" ? local.postgres_private_dns_zone_id : null

  # The public path: no VNet, and the firewall lets in the cluster's outbound
  # addresses only.
  public_network_access_enabled = local.public_path
  allowed_ip_ranges             = local.public_path ? var.workload_egress_ip_ranges : []

  administrator_login    = var.postgres_admin_login
  administrator_password = local.postgres_admin_password
  sku_name               = var.postgres_sku
  postgres_version       = var.postgres_version
  storage_mb             = var.postgres_storage_mb

  backup_retention_days        = var.postgres_backup_retention_days
  geo_redundant_backup_enabled = var.postgres_geo_redundant_backup_enabled
  auto_grow_enabled            = var.postgres_auto_grow_enabled
  high_availability_enabled    = var.postgres_high_availability_enabled
  delete_protection_enabled    = var.postgres_delete_protection_enabled
  cmk_key_vault_key_id         = local.cmk_key_vault_key_id
  cmk_identity_id              = local.cmk_identity_id

  # The encryption identity must hold the crypto role before the server wraps its
  # data key with the customer-managed key. The zone link must exist before the
  # server registers its record in a zone we created for a brought network.
  depends_on = [
    azurerm_role_assignment.cmk_encryptor,
    azurerm_private_dns_zone_virtual_network_link.postgres,
  ]
}

data "azurerm_postgresql_flexible_server" "existing" {
  count               = local.create_postgres ? 0 : 1
  name                = local.existing.postgres.name
  resource_group_name = local.existing.postgres.rg
}
