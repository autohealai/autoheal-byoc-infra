# Object storage: the storage account and container we create, or the customer's
# account read through a data source, with our container created in it unless
# create_storage_container = false.

module "blob" {
  source = "../../modules/azure/blob"
  count  = local.create_storage ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location
  container_name      = var.storage_container_name

  # Default-deny firewall. The allow list covers the apply host and the cluster's
  # outbound addresses (when private endpoints are off). On the public path the
  # cluster owner adds a network rule for the AKS subnet after the apply
  # (required_cluster_owner_actions); the module leaves subnet rules alone.
  network_default_action = var.storage_network_default_action
  allowed_ip_ranges      = distinct(concat(var.deployer_ip_ranges, var.workload_egress_ip_ranges))

  account_replication_type             = var.blob_replication_type
  blob_soft_delete_retention_days      = var.blob_soft_delete_retention_days
  container_soft_delete_retention_days = var.blob_container_soft_delete_retention_days
  pitr_enabled                         = var.blob_pitr_enabled
  blob_restore_days                    = var.blob_restore_days
  cmk_key_vault_key_id                 = local.cmk_key_vault_key_versionless_id
  cmk_identity_id                      = local.cmk_identity_id

  depends_on = [azurerm_role_assignment.cmk_encryptor]
}

data "azurerm_storage_account" "existing" {
  count               = local.create_storage ? 0 : 1
  name                = local.existing.storage.name
  resource_group_name = local.existing.storage.rg
}

# Created through the management plane (storage_account_id), so it needs no
# data-plane access to the brought account.
resource "azurerm_storage_container" "this" {
  count                 = !local.create_storage && var.create_storage_container ? 1 : 0
  name                  = var.storage_container_name
  storage_account_id    = var.existing_storage_account_id
  container_access_type = "private"
}
