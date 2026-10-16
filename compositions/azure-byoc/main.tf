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

  # Customer-managed key wiring. These are the key id + encryption identity id that
  # Postgres and Blob consume; both are empty strings when cmk_enabled = false, which
  # selects the Microsoft-managed key in each module. Created below from the stack's
  # own Key Vault.
  cmk_key_vault_key_id = var.cmk_enabled ? azurerm_key_vault_key.cmk[0].id : ""
  cmk_identity_id      = var.cmk_enabled ? azurerm_user_assigned_identity.cmk[0].id : ""

  # The storage account takes the VERSIONLESS key id so it auto-rotates to new key
  # versions; Postgres Flexible requires a versioned id (the provider rejects a
  # versionless one), so it keeps cmk_key_vault_key_id above.
  cmk_key_vault_key_versionless_id = var.cmk_enabled ? azurerm_key_vault_key.cmk[0].versionless_id : ""
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags

  # Blob and Key Vault default to deny-all firewalls, so a workable install must open two
  # DISTINCT data-plane paths — they do not share a source IP:
  #   1. Apply-time. Terraform seeds Key Vault secrets and creates the blob container from
  #      the apply host over the data plane. Its public egress IP must be allow-listed via
  #      deployer_ip_ranges (unless default_action = Allow). A private endpoint does NOT
  #      cover the apply host unless Terraform runs inside the VNet, which this composition
  #      does not assume — so seeding always takes the public+allow-list path and never
  #      races the (sibling) private-endpoint module.
  #   2. Runtime. AKS pods (ESO reading secrets, the app reading blobs) egress via the
  #      cluster's outbound IP, NOT the apply host, so deployer_ip_ranges does nothing for
  #      them. That path needs a private endpoint, the cluster outbound CIDR(s) in
  #      workload_egress_ip_ranges, or default_action = Allow.
  # Both are checked at plan time so a missing path surfaces here, not as a 403 mid-apply
  # or a silently broken ESO at runtime.
  lifecycle {
    precondition {
      condition = (
        length(var.deployer_ip_ranges) > 0 ||
        (var.storage_network_default_action == "Allow" && var.key_vault_network_default_action == "Allow")
      )
      error_message = "No apply-time path to Blob/Key Vault. Terraform seeds Key Vault secrets and creates the blob container from the apply host over the data plane. Set deployer_ip_ranges to the apply host's public egress CIDR(s), or set storage_network_default_action and key_vault_network_default_action to \"Allow\" for a throwaway install. A private endpoint does not cover the apply host unless Terraform runs inside the VNet."
    }
    precondition {
      condition = (
        var.private_endpoints_enabled ||
        length(var.workload_egress_ip_ranges) > 0 ||
        (var.storage_network_default_action == "Allow" && var.key_vault_network_default_action == "Allow")
      )
      error_message = "No runtime path to Blob/Key Vault. AKS pods (ESO, app) egress via the cluster's outbound IP, not the apply host, so deployer_ip_ranges does not help them. Set private_endpoints_enabled = true, or set workload_egress_ip_ranges to the cluster's outbound CIDR(s), or set storage_network_default_action and key_vault_network_default_action to \"Allow\" for a throwaway install."
    }
  }
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

  # Backup, HA and encryption at rest. Defaults preserve current behaviour; the
  # install profile sets production values. geo-redundant backup and CMK are
  # create-time only (see variables.tf).
  backup_retention_days        = var.postgres_backup_retention_days
  geo_redundant_backup_enabled = var.postgres_geo_redundant_backup_enabled
  auto_grow_enabled            = var.postgres_auto_grow_enabled
  high_availability_enabled    = var.postgres_high_availability_enabled
  delete_protection_enabled    = var.postgres_delete_protection_enabled
  cmk_key_vault_key_id         = local.cmk_key_vault_key_id
  cmk_identity_id              = local.cmk_identity_id

  # The encryption identity must already hold the crypto role on the vault before the
  # server wraps its data key with the CMK (no-op when cmk_enabled = false).
  depends_on = [azurerm_role_assignment.cmk_encryptor]
}

module "blob" {
  source = "../../modules/azure/blob"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  # Firewall posture. Default-deny; the allow-list covers both the apply host
  # (deployer_ip_ranges, for creating the container) and the cluster's outbound IP
  # (workload_egress_ip_ranges, for app pods when private endpoints are off).
  network_default_action = var.storage_network_default_action
  allowed_ip_ranges      = distinct(concat(var.deployer_ip_ranges, var.workload_egress_ip_ranges))

  # Redundancy, soft delete, point-in-time restore and encryption at rest. Defaults
  # preserve current behaviour; the install profile sets production values.
  account_replication_type             = var.blob_replication_type
  blob_soft_delete_retention_days      = var.blob_soft_delete_retention_days
  container_soft_delete_retention_days = var.blob_container_soft_delete_retention_days
  pitr_enabled                         = var.blob_pitr_enabled
  blob_restore_days                    = var.blob_restore_days
  cmk_key_vault_key_id                 = local.cmk_key_vault_key_versionless_id
  cmk_identity_id                      = local.cmk_identity_id

  depends_on = [azurerm_role_assignment.cmk_encryptor]
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

  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  deployer_object_id         = data.azurerm_client_config.current.object_id
  purge_protection_enabled   = var.key_vault_purge_protection_enabled
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days

  # Firewall posture. Default-deny; the allow-list covers both the apply host
  # (deployer_ip_ranges, for seeding the secrets below) and the cluster's outbound IP
  # (workload_egress_ip_ranges, for ESO when private endpoints are off).
  network_default_action = var.key_vault_network_default_action
  allowed_ip_ranges      = distinct(concat(var.deployer_ip_ranges, var.workload_egress_ip_ranges))

  secrets = {
    "postgres-password" = random_password.postgres.result
    "postgres-host"     = module.postgres.host
    "postgres-user"     = module.postgres.administrator_login
  }
}

# Customer-managed key (CMK) for encryption at rest of Postgres and Blob. Off by
# default; when cmk_enabled = true a dedicated user-assigned identity holds the
# encryption role and an RSA key is created in the stack's own Key Vault. Both the
# database and the storage account encrypt with this one key. CMK is CREATE-TIME
# ONLY on Postgres, and the vault MUST have purge protection on (enforced below).
#
# RBAC note: creating the key needs a data-plane role for the deployer (Crypto
# Officer), and the encryption identity needs Crypto Service Encryption User. As
# with the secret seeding, Azure RBAC propagation can lag a few seconds, so a first
# apply may need one retry if it races.
resource "azurerm_user_assigned_identity" "cmk" {
  count               = var.cmk_enabled ? 1 : 0
  name                = "id-${var.namespace}-${var.environment}-${var.name}-cmk"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "cmk_deployer" {
  count                = var.cmk_enabled ? 1 : 0
  scope                = module.keyvault.key_vault_id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "cmk_encryptor" {
  count                = var.cmk_enabled ? 1 : 0
  scope                = module.keyvault.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.cmk[0].principal_id
}

resource "azurerm_key_vault_key" "cmk" {
  count        = var.cmk_enabled ? 1 : 0
  name         = "${var.namespace}-${var.environment}-${var.name}-cmk"
  key_vault_id = module.keyvault.key_vault_id
  key_type     = "RSA"
  key_size     = 3072
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  depends_on = [azurerm_role_assignment.cmk_deployer]

  lifecycle {
    precondition {
      condition     = var.key_vault_purge_protection_enabled
      error_message = "cmk_enabled = true requires key_vault_purge_protection_enabled = true: a Key Vault that holds a customer-managed encryption key must have purge protection on, or Azure refuses to use the key."
    }
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

  # Access controls. Supplying admin_group_object_ids turns on managed-Entra RBAC and
  # disables the static-cert local admin accounts. api_server_authorized_ip_ranges locks
  # the public API server to known CIDRs; private_cluster_enabled removes it entirely.
  admin_group_object_ids          = var.admin_group_object_ids
  tenant_id                       = var.aks_admin_tenant_id
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
  private_cluster_enabled         = var.private_cluster_enabled
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
