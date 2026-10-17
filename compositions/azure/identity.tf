# Workload identities, one per chart role. Each is federated to the chart's
# service accounts through the cluster's OIDC issuer, so pods get Entra tokens
# with no stored credential.
#
#   secrets        read the vault (Key Vault Secrets User). Used by the chart's
#                  autoheal-hooks service account: the secrets-sync hook Job and
#                  CronJob mount the SecretProviderClass and copy the entries
#                  into Kubernetes Secrets. No service pod mounts the vault.
#   api-server     read and write blob storage (Storage Blob Data
#                  Contributor on the storage account). The account scope is
#                  needed: the Git Registry creates one autoheal-<tenant-id>
#                  container per tenant at runtime, which a grant scoped to
#                  one container does not allow.
#   agents-worker  the same blob grant, for the agents services.
#
# Their client IDs go into global.infra.identities. With
# create_role_assignments = false the identities and federations are still
# created, but the grants are listed in required_role_assignments instead.

module "secrets_identity" {
  source = "../../modules/azure/secrets-identity"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["secrets"]
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location
  oidc_issuer_url     = local.oidc_issuer
  key_vault_id        = local.key_vault_id

  service_accounts = [
    for sa in var.service_accounts.secrets : { namespace = var.service_accounts.namespace, service_account = sa }
  ]
  role_assignment_enabled = var.create_role_assignments
}

module "api_server_identity" {
  source = "../../modules/azure/workload-identity"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["api-server"]
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location
  oidc_issuer_url     = local.oidc_issuer

  federated_service_accounts = [
    for sa in var.service_accounts.api_server : { namespace = var.service_accounts.namespace, service_account = sa }
  ]

  kv_role_enabled    = false
  storage_account_id = local.storage_account_id
  blob_role_enabled  = var.create_role_assignments
  acr_pull_enabled   = false
}

module "agents_worker_identity" {
  source = "../../modules/azure/workload-identity"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["agents-worker"]
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location
  oidc_issuer_url     = local.oidc_issuer

  federated_service_accounts = [
    for sa in var.service_accounts.agents_worker : { namespace = var.service_accounts.namespace, service_account = sa }
  ]

  kv_role_enabled    = false
  storage_account_id = local.storage_account_id
  blob_role_enabled  = var.create_role_assignments
  acr_pull_enabled   = false
}
