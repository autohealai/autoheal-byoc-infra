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

  # Firewall: default-deny. The app reaches the account over a private endpoint, so
  # the public network path stays closed. bypass=AzureServices lets trusted Azure
  # platform services through; allowed_ip_ranges opens the apply host's public IP
  # when the Terraform run must create the container / seed data over the data plane
  # (default_action=Deny blocks that otherwise). Set network_default_action=Allow
  # only for throwaway/playground accounts with no private endpoint.
  network_rules {
    default_action = var.network_default_action
    bypass         = ["AzureServices"]
    ip_rules       = var.allowed_ip_ranges
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
