# PostgreSQL Flexible Server, provisioned + private (VNet-integrated). The AWS
# analogue is modules/aws/aurora-postgres (Aurora). BYOC data-tier policy is
# PROVISIONED, never serverless/burstable, for a real install.
#
# Private DNS + delegated subnet = no public endpoint; the server is only
# reachable from the VNet (AKS pods). Both the delegated subnet and the private
# DNS zone come from modules/azure/vnet (subnet_db_id, pg_private_dns_zone_id).
#
# With public_network_access_enabled = true instead, the server has no VNet and
# a firewall rule per allowed_ip_ranges entry, for clients that reach it from
# their public addresses. Azure fixes the choice when the server is created.
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

  # Storage auto-grow: the server expands its disk before it fills, which is the
  # single most important availability setting (a full disk takes the database
  # read-only). Applied in place, no downtime. The AWS twin (Aurora) grows
  # automatically, so this brings Azure to parity.
  auto_grow_enabled = var.auto_grow_enabled

  # Backups. Azure takes automatic full + incremental + transaction-log backups and
  # keeps them for backup_retention_days (1-35); any point in that window can be
  # restored (point-in-time restore). geo_redundant_backup copies every backup to the
  # Azure paired region so they survive a whole-region outage.
  # NOTE: geo_redundant_backup_enabled is CREATE-TIME ONLY — it cannot be changed on
  # an existing server. backup_retention_days can be changed at any time.
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  # High availability: a hot standby in a second availability zone with automatic
  # failover. Can be turned on or off on an existing server (region must have zones
  # and the SKU must be General Purpose or Memory Optimized, not Burstable).
  dynamic "high_availability" {
    for_each = var.high_availability_enabled ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  # Customer-managed key (CMK): encrypt the database at rest with a key the customer
  # owns in Key Vault, instead of the Microsoft-managed key. Off by default (empty
  # key id); the Microsoft-managed key is always in effect when this is unset.
  # NOTE: CMK is CREATE-TIME ONLY for Flexible Server, and the Key Vault holding the
  # key must have purge protection enabled.
  dynamic "customer_managed_key" {
    for_each = var.cmk_key_vault_key_id != "" ? [1] : []
    content {
      key_vault_key_id                  = var.cmk_key_vault_key_id
      primary_user_assigned_identity_id = var.cmk_identity_id
    }
  }

  dynamic "identity" {
    for_each = var.cmk_identity_id != "" ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.cmk_identity_id]
    }
  }

  delegated_subnet_id           = var.public_network_access_enabled ? null : var.delegated_subnet_id
  private_dns_zone_id           = var.public_network_access_enabled ? null : var.private_dns_zone_id
  public_network_access_enabled = var.public_network_access_enabled

  tags = module.this.tags

  lifecycle {
    # The server name plus the private DNS zone are immutable; guard against an
    # accidental zone/AZ change forcing a destroy/recreate of the database.
    ignore_changes = [zone]

    # CMK + geo-redundant backup together require a second, paired-region key
    # (geo_backup_key_vault_key_id + geo_backup_user_assigned_identity_id) to encrypt
    # the backup copy that lands in the paired region. This module wires only the
    # primary key, so Azure rejects the combination at create time with a cryptic
    # CMKInvalidEncryptionParameters 400 after a multi-minute apply. Catch it here at
    # plan time with a readable message instead. Enable one or the other until the
    # paired-region geo-backup key is supported.
    precondition {
      condition     = !(var.cmk_key_vault_key_id != "" && var.geo_redundant_backup_enabled)
      error_message = "customer-managed key (cmk_enabled) and geo-redundant backup (postgres_geo_redundant_backup_enabled) cannot both be enabled: together they require a paired-region geo-backup key that is not yet supported. Enable one or the other."
    }

    # A customer-managed key needs its encryption identity: the key id and identity id
    # must be set together (both or neither), or the server gets a CMK block with no
    # identity and Azure rejects it.
    precondition {
      condition     = (var.cmk_key_vault_key_id != "") == (var.cmk_identity_id != "")
      error_message = "cmk_key_vault_key_id and cmk_identity_id must be set together (both or neither)."
    }
  }
}

# Delete protection: an Azure resource lock that blocks deletion of the
# system-of-record database (deleting a Flexible Server also deletes its backups).
# This is the Azure equivalent of the AWS twin's deletion_protection + final
# snapshot. Off by default; set delete_protection_enabled = true for a real install.
resource "azurerm_management_lock" "no_delete" {
  count      = var.delete_protection_enabled ? 1 : 0
  name       = "${module.this.id}-no-delete"
  scope      = azurerm_postgresql_flexible_server.this.id
  lock_level = "CanNotDelete"
  notes      = "Protects the system-of-record database from accidental deletion. Remove by setting delete_protection_enabled = false."
}

# One rule per allowed range. A bare address is a /32.
locals {
  firewall_rules = var.public_network_access_enabled ? {
    for r in var.allowed_ip_ranges : "allow-${replace(replace(r, ".", "-"), "/", "-")}" => {
      start = cidrhost(strcontains(r, "/") ? r : "${r}/32", 0)
      end   = cidrhost(strcontains(r, "/") ? r : "${r}/32", -1)
    }
  } : {}
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed" {
  for_each         = local.firewall_rules
  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = each.value.start
  end_ip_address   = each.value.end
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = join(",", var.extensions)
}
