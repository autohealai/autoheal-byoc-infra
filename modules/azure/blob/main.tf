# Blob storage for attachments, knowledge base and the Git Registry. The AWS analogue is
# modules/aws/s3. The app reaches it keyless via the app workload identity
# (Storage Blob Data Contributor, granted in modules/azure/workload-identity), so
# no account key is stored anywhere.
#
# Storage account names reject dashes and cap at 24 chars, so we sanitize
# module.this.id (strip the delimiter, lowercase, truncate) rather than making
# the consumer think about it. account_name_override forces an exact name when a
# fixed convention (e.g. stautoheal<env>) is required.

locals {
  account_name = var.account_name_override != "" ? var.account_name_override : substr(lower(replace(module.this.id, "/[^0-9A-Za-z]/", "")), 0, 24)
}

resource "azurerm_storage_account" "this" {
  name                     = local.account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
  tags                     = module.this.tags

  # The Git Registry keeps one container per tenant (autoheal-<tenant-id>) in this
  # account and needs a flat namespace: Copy Blob + delete is its rename, and
  # hierarchical namespace changes those semantics. Set it explicitly; it cannot
  # change after create.
  is_hns_enabled = false

  # Versioning is the Azure equivalent of the per-bucket S3 versioning the app sets
  # on AWS. On Azure it is an account setting that the app's data-plane identity
  # cannot change, so this module owns it. No lifecycle rule moves blobs to a cool
  # or archive tier: the Git Registry must read any object immediately.
  #
  # This block makes Terraform own every blob-service property. The provider turns
  # off a retention policy that the block omits, so soft delete is set here
  # explicitly; otherwise an apply would silently disable soft delete that an
  # operator enabled in the portal.
  blob_properties {
    versioning_enabled = var.versioning_enabled

    # Point-in-time restore: rewind the whole account's block blobs to an earlier
    # moment (recovers from a bad bulk overwrite or delete). It needs versioning,
    # the change feed and soft delete on, and the restore window must be shorter
    # than the soft-delete window. Off by default.
    change_feed_enabled = var.pitr_enabled

    # The change feed logs every blob change and Azure keeps it forever unless a
    # retention is set. On a busy per-tenant account that log grows without bound, so
    # cap it just past the restore window (the only thing PITR needs it for). Only
    # valid while the change feed is on.
    change_feed_retention_in_days = var.pitr_enabled ? var.blob_restore_days + 1 : null

    # Last-access tracking is NOT a PITR requirement (PITR needs versioning + change
    # feed + soft delete) and adds per-operation overhead. There is no access-based
    # lifecycle rule here, so keep it off.
    last_access_time_enabled = false

    dynamic "restore_policy" {
      for_each = var.pitr_enabled ? [1] : []
      content {
        days = var.blob_restore_days
      }
    }

    dynamic "delete_retention_policy" {
      for_each = var.blob_soft_delete_retention_days > 0 ? [1] : []
      content {
        days = var.blob_soft_delete_retention_days
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.container_soft_delete_retention_days > 0 ? [1] : []
      content {
        days = var.container_soft_delete_retention_days
      }
    }
  }

  # Customer-managed key (CMK): encrypt the account at rest with a key the customer
  # owns in Key Vault, instead of the Microsoft-managed key. Off by default (empty
  # key id); the Microsoft-managed key is always in effect when this is unset. The
  # vault holding the key must have purge protection on.
  dynamic "identity" {
    for_each = var.cmk_identity_id != "" ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.cmk_identity_id]
    }
  }

  dynamic "customer_managed_key" {
    for_each = var.cmk_key_vault_key_id != "" ? [1] : []
    content {
      key_vault_key_id          = var.cmk_key_vault_key_id
      user_assigned_identity_id = var.cmk_identity_id
    }
  }

  # Firewall: default-deny. The app reaches the account over a private endpoint, so
  # the public network path stays closed. bypass=AzureServices lets trusted Azure
  # platform services through; allowed_ip_ranges opens the apply host's public IP
  # when the Terraform run must create the container / seed data over the data plane
  # (default_action=Deny blocks that otherwise). Set network_default_action=Allow
  # only for throwaway/playground accounts with no private endpoint.
  # The storage firewall takes a single address without a prefix and rejects /31
  # and /32, so a /32 range is written as the bare address.
  network_rules {
    default_action = var.network_default_action
    bypass         = ["AzureServices"]
    ip_rules       = distinct([for r in var.allowed_ip_ranges : trimsuffix(r, "/32")])
  }

  lifecycle {
    # IP rules do not apply to clients in the account's region, which reach the
    # account over Azure's network. Such clients come in through a subnet rule,
    # and that rule needs rights on the client's subnet (the Microsoft.Storage
    # service endpoint and joinViaServiceEndpoint), which belong to whoever owns
    # that network. So the subnet's owner adds it with
    # `az storage account network-rule add`, and this module neither sets nor
    # removes subnet rules.
    ignore_changes = [network_rules[0].virtual_network_subnet_ids]

    # Azure rejects a restore window that is not shorter than the soft-delete window;
    # fail at plan time with a clear message instead of a mid-apply 400.
    precondition {
      condition     = !var.pitr_enabled || var.blob_restore_days < var.blob_soft_delete_retention_days
      error_message = "blob_restore_days must be strictly less than blob_soft_delete_retention_days when pitr_enabled = true."
    }

    # PITR also requires versioning and blob soft delete to be on; without them Azure
    # rejects the restore policy mid-apply. Catch it at plan time.
    precondition {
      condition     = !var.pitr_enabled || (var.versioning_enabled && var.blob_soft_delete_retention_days > 0)
      error_message = "pitr_enabled = true requires versioning_enabled = true and blob_soft_delete_retention_days > 0."
    }

    # A customer-managed key needs its encryption identity: the key id and identity id
    # must be set together (both or neither), or the storage account gets a CMK block
    # with no identity and Azure rejects it.
    precondition {
      condition     = (var.cmk_key_vault_key_id != "") == (var.cmk_identity_id != "")
      error_message = "cmk_key_vault_key_id and cmk_identity_id must be set together (both or neither)."
    }
  }
}

# Expire noncurrent versions, as modules/aws/s3 does. Without it every overwrite
# and every Git Registry rename (Copy Blob + delete) keeps the old version forever.
# The rule is account-wide (no prefix): a management-policy prefix must start with
# a container name, and the Git Registry has one container per tenant. It deletes
# old versions only; no rule touches the tier of current blobs.
resource "azurerm_storage_management_policy" "this" {
  count              = var.versioning_enabled && var.noncurrent_version_expiration_days > 0 ? 1 : 0
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "expire-noncurrent-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = var.noncurrent_version_expiration_days
      }
    }
  }
}

resource "azurerm_storage_container" "attachments" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
