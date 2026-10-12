# Full Azure BYOC stack: wires the modules/azure/* building blocks into one install
# and emits the cross-cloud output contract. The AWS twin is compositions/aws-byoc.
#
# Scope: everything up to a running cluster + data tier + identities. One thing is
# deliberately NOT here:
#   - The runner VMSS. It needs temporal_host (the internal LB IP), which only
#     exists after the app + Temporal are deployed, so it is a separate apply after
#     the app install (feed-forward), matching the AWS runner unit.

locals {
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.namespace}-${var.environment}-${var.name}"

  # PG Flexible private DNS zone: the label prefix must be a valid DNS label and the
  # suffix is fixed by Azure.
  pg_dns_zone_name = "${var.namespace}-${var.environment}.private.postgres.database.azure.com"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Admin password for PostgreSQL; seeded into Key Vault, never surfaced as a root
# output. ESO syncs it into the cluster from the vault.
resource "random_password" "postgres" {
  length           = 32
  special          = true
  override_special = "!#$%*-_=+"
}

module "vnet" {
  source = "../../modules/azure/vnet"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name       = azurerm_resource_group.this.name
  location                  = var.location
  address_space             = var.address_space
  pg_private_dns_zone_name  = local.pg_dns_zone_name
  private_endpoints_enabled = var.private_endpoints_enabled
}

module "postgres" {
  source = "../../modules/azure/postgres-flexible"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["db"]
  tags        = var.tags

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  delegated_subnet_id = module.vnet.subnet_db_id
  private_dns_zone_id = module.vnet.pg_private_dns_zone_id

  administrator_password = random_password.postgres.result
  sku_name               = var.postgres_sku_name
  storage_mb             = var.postgres_storage_mb
}

module "blob" {
  source = "../../modules/azure/blob"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
}

module "acr" {
  source = "../../modules/azure/acr"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = var.acr_sku
}

module "keyvault" {
  source = "../../modules/azure/keyvault"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name      = azurerm_resource_group.this.name
  location                 = var.location
  tenant_id                = data.azurerm_client_config.current.tenant_id
  deployer_object_id       = data.azurerm_client_config.current.object_id
  purge_protection_enabled = var.key_vault_purge_protection_enabled

  secrets = {
    "postgres-password" = random_password.postgres.result
    "postgres-host"     = module.postgres.host
    "postgres-user"     = module.postgres.administrator_login
  }
}

module "aks" {
  source = "../../modules/azure/aks"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  vnet_id            = module.vnet.vnet_id
  vnet_subnet_id     = module.vnet.subnet_aks_id
  kubernetes_version = var.kubernetes_version
  node_vm_size       = var.node_vm_size
  node_min_count     = var.node_min_count
  node_max_count     = var.node_max_count
  acr_id             = module.acr.acr_id
}

module "workload_identity" {
  source = "../../modules/azure/workload-identity"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["app"]
  tags        = var.tags

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  oidc_issuer_url            = module.aks.oidc_issuer_url
  federated_service_accounts = var.federated_service_accounts
  # The app identity does NOT read Key Vault: app pods consume the Kubernetes
  # Secrets that ESO syncs, and ESO reads the vault with its own dedicated identity
  # (module.eso_identity below). Keeping KV read off the app identity is the
  # least-privilege model and mirrors the EKS split (app role != ESO role).
  key_vault_id       = module.keyvault.key_vault_id
  kv_role_enabled    = false
  storage_account_id = module.blob.account_id
  acr_id             = ""
}

# Dedicated, least-scoped identity for the External Secrets Operator. ESO reads
# Key Vault with THIS identity (Key Vault Secrets User), federated to its own
# controller ServiceAccount. The operator install + ClusterSecretStore +
# ExternalSecrets are in-cluster objects owned by the app/install layer, which
# consumes the outputs below (client_id, tenant_id) plus the vault_uri.
module "eso_identity" {
  source = "../../modules/azure/external-secrets"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["eso"]
  tags        = var.tags

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  oidc_issuer_url = module.aks.oidc_issuer_url
  key_vault_id    = module.keyvault.key_vault_id
}

# Optional private endpoints for Blob + Key Vault (zones come from the vnet module
# when private_endpoints_enabled = true).
module "pe_blob" {
  source = "../../modules/azure/private-endpoint"
  count  = var.private_endpoints_enabled ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["blob"]
  tags        = var.tags

  resource_group_name  = azurerm_resource_group.this.name
  location             = var.location
  subnet_id            = module.vnet.subnet_pe_id
  target_resource_id   = module.blob.account_id
  subresource_names    = ["blob"]
  private_dns_zone_ids = [module.vnet.blob_private_dns_zone_id]
}

module "pe_vault" {
  source = "../../modules/azure/private-endpoint"
  count  = var.private_endpoints_enabled ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["vault"]
  tags        = var.tags

  resource_group_name  = azurerm_resource_group.this.name
  location             = var.location
  subnet_id            = module.vnet.subnet_pe_id
  target_resource_id   = module.keyvault.key_vault_id
  subresource_names    = ["vault"]
  private_dns_zone_ids = [module.vnet.vault_private_dns_zone_id]
}
