# Blob storage for attachments / knowledge base. The AWS analogue is
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
}

resource "azurerm_storage_container" "attachments" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
