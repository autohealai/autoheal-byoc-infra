# Azure BYOC CONNECT: the Nomura-style install where the customer provisions all
# base infrastructure and Autoheal only connects the app to it. This composition
# reads the existing VNet/AKS/PG/Key Vault/Redis/ACR/Storage via data sources,
# creates the app and ESO workload identities that bind Autoheal pods to those
# resources, optionally seeds the data-tier secrets, and emits the SAME output contract as the
# create composition (compositions/azure-byoc) so the app install is identical.
#
# What it CREATES: two user-assigned identities, both federated against the existing
# cluster's OIDC issuer —
#   - an app identity for the chart ServiceAccounts, granted Storage Blob Data
#     Contributor (+ optional AcrPull). It is NOT granted Key Vault access: app pods
#     consume the Kubernetes Secrets that ESO syncs.
#   - a dedicated ESO identity (module.eso_identity) federated to the External Secrets
#     controller ServiceAccount, granted Key Vault Secrets User so ESO reads the vault.
# Plus optional seed secrets into the existing Key Vault. Everything else is read-only.

data "azurerm_client_config" "current" {}

# --- Existing resources (read-only) ---------------------------------------

data "azurerm_kubernetes_cluster" "existing" {
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group_name
}

data "azurerm_postgresql_flexible_server" "existing" {
  name                = var.postgres_server_name
  resource_group_name = var.resource_group_name
}

data "azurerm_key_vault" "existing" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
}

data "azurerm_redis_cache" "existing" {
  name                = var.redis_cache_name
  resource_group_name = var.resource_group_name
}

data "azurerm_container_registry" "existing" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
}

data "azurerm_storage_account" "existing" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

# --- Guard: the customer's Key Vault must use RBAC authorization -----------

# Every Key Vault grant this composition makes is an Azure RBAC role assignment:
# the ESO identity's Key Vault Secrets User and (when seeding) the deployer's Secrets
# Officer. On an access-policy vault (rbac_authorization_enabled = false) those
# assignments apply cleanly but grant NOTHING at the data plane — ESO would 403 at
# runtime and the seed writes would fail. Fail the plan here instead of shipping a
# green apply with a dead runtime; the customer must enable RBAC on the vault (or
# switch us to access-policy grants, which this composition does not emit).
resource "terraform_data" "kv_rbac_guard" {
  lifecycle {
    precondition {
      condition     = data.azurerm_key_vault.existing.rbac_authorization_enabled
      error_message = "Key Vault '${var.key_vault_name}' must use RBAC authorization (rbac_authorization_enabled = true). This composition grants Key Vault access via Azure RBAC role assignments, which have no effect on an access-policy vault."
    }
  }
}

# --- Guard: the customer's Storage Account must have a flat namespace ------

# The Git Registry keeps one container per tenant in this account and renames with
# Copy Blob + delete. Hierarchical namespace (ADLS Gen2) changes those semantics, and
# it cannot be turned off after the account exists. Fail the plan instead of shipping
# a green apply that breaks the registry at runtime. Versioning is also required, but
# the data source does not expose it; the README gives the command to check it.
resource "terraform_data" "storage_hns_guard" {
  lifecycle {
    precondition {
      condition     = !data.azurerm_storage_account.existing.is_hns_enabled
      error_message = "Storage Account '${var.storage_account_name}' has hierarchical namespace on (ADLS Gen2). The Git Registry needs a flat namespace. Use an account with is_hns_enabled = false."
    }
  }
}

# --- App workload identity (the thing we create) --------------------------

module "workload_identity" {
  source = "../../modules/azure/workload-identity"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["app"]
  tags        = var.tags

  resource_group_name = var.resource_group_name
  location            = var.location

  oidc_issuer_url            = data.azurerm_kubernetes_cluster.existing.oidc_issuer_url
  federated_service_accounts = var.federated_service_accounts

  # The app identity does NOT read Key Vault: app pods consume the Kubernetes
  # Secrets that ESO syncs, and ESO reads the vault with its own dedicated identity
  # (module.eso_identity below). Keeping KV read off the app identity is the
  # least-privilege model and mirrors the create composition (azure-byoc) and the
  # EKS split (app role != ESO role).
  #
  # CROSS-REPO CONTRACT (important): because the app identity holds NO Key Vault grant,
  # the ONLY principal that can read Key Vault is module.eso_identity, which is granted
  # Key Vault Secrets User on the federated subject
  # system:serviceaccount:external-secrets:external-secrets (the external-secrets module
  # defaults). The app install (install-aks.sh / the chart) MUST therefore (a) deploy the
  # ESO controller under exactly that namespace/ServiceAccount, and (b) stamp it with the
  # eso_identity_client_id output. If it deploys ESO under a different ns/SA or ignores the
  # outputs, no identity can read Key Vault and every app secret fails to sync — a green
  # apply with a dead runtime. Change the federated subject here and in the installer together.
  key_vault_id       = data.azurerm_key_vault.existing.id
  kv_role_enabled    = false
  storage_account_id = data.azurerm_storage_account.existing.id
  acr_id             = var.grant_app_acr_pull ? data.azurerm_container_registry.existing.id : ""
}

# --- ESO identity (reads the existing Key Vault) --------------------------

# Dedicated, least-scoped identity for the External Secrets Operator, federated to
# the EXISTING cluster's OIDC issuer and granted Key Vault Secrets User on the
# EXISTING vault. The installer (install-aks.sh, azurekeyvault path) reads the
# eso_identity_* outputs to stamp the ESO controller ServiceAccount and wire the
# ClusterSecretStore (provider.azurekv). Same module and output contract as the
# create composition (azure-byoc) so the app install is identical either way.
module "eso_identity" {
  source = "../../modules/azure/external-secrets"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["eso"]
  tags        = var.tags

  resource_group_name = var.resource_group_name
  location            = var.location

  oidc_issuer_url = data.azurerm_kubernetes_cluster.existing.oidc_issuer_url
  key_vault_id    = data.azurerm_key_vault.existing.id
}

# --- Optional secret seeding into the existing Key Vault ------------------

locals {
  seed_secrets = var.seed_secrets_enabled ? merge(
    {
      "redis-host"     = data.azurerm_redis_cache.existing.hostname
      "redis-port"     = tostring(data.azurerm_redis_cache.existing.ssl_port)
      "redis-password" = data.azurerm_redis_cache.existing.primary_access_key
      "postgres-host"  = data.azurerm_postgresql_flexible_server.existing.fqdn
      "postgres-user"  = var.postgres_admin_login
    },
    var.additional_secrets,
  ) : {}
}

# RBAC-mode vaults enforce data-plane RBAC; grant the deployer Secrets Officer on
# the EXISTING vault so the seed can write. Scoped to the vault, nothing else.
resource "azurerm_role_assignment" "deployer_kv" {
  count                = var.seed_secrets_enabled ? 1 : 0
  scope                = data.azurerm_key_vault.existing.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "seed" {
  for_each     = nonsensitive(toset(keys(local.seed_secrets)))
  name         = each.value
  value        = local.seed_secrets[each.value]
  key_vault_id = data.azurerm_key_vault.existing.id

  depends_on = [azurerm_role_assignment.deployer_kv]
}
