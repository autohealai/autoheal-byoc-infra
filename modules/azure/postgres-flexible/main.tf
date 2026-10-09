# PostgreSQL Flexible Server, provisioned + private (VNet-integrated). The AWS
# analogue is modules/aws/rds-cluster (Aurora). BYOC data-tier policy is
# PROVISIONED, never serverless/burstable, for a real install.
#
# Private DNS + delegated subnet = no public endpoint; the server is only
# reachable from the VNet (AKS pods). Both the delegated subnet and the private
# DNS zone come from modules/azure/vnet (subnet_db_id, pg_private_dns_zone_id).
#
# The azure.extensions allow-list is set as a server configuration so
# CREATE EXTENSION (pgvector, btree_gin, ...) succeeds. Azure Flexible rejects any
# extension not pre-listed, a gap RDS did not have: every extension must appear
# here BEFORE any CREATE EXTENSION runs.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

resource "azurerm_postgresql_flexible_server" "this" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.postgres_version

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  sku_name   = var.sku_name
  storage_mb = var.storage_mb

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = false

  tags = module.this.tags

  lifecycle {
    # The server name plus the private DNS zone are immutable; guard against an
    # accidental zone/AZ change forcing a destroy/recreate of the database.
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = join(",", var.extensions)
}
