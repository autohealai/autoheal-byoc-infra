# Vault entries. Terraform writes every secret the chart reads into the vault
# (created or brought) in this apply, so the install needs no manual secret step.
# The chart mounts them through the Key Vault CSI driver (global.secrets.mode =
# keyvault-csi).
#
# Generated once and kept across upgrades: the per-service database passwords,
# the JWT signing key, the Zitadel master key, the auth session secret and the
# first admin password. Connection strings that carry a password are rebuilt when
# the host or the password changes; the password is URL-encoded.
#
# Passed in by the customer (sensitive inputs): the Postgres admin password of a
# brought server, the LLM API key, the SSO client secret and a corporate TLS
# certificate. Each entry exists only when its input is set.
#
# Database names and roles the chart's db-provision hook creates with these
# passwords: app_user owns app, agents_user owns agents, temporal_user owns
# temporal and temporal_visibility, zitadel_user owns zitadel.

resource "random_password" "db" {
  for_each = toset(["api-server", "agents", "temporal", "zitadel"])
  length   = 32
  special  = false
}

resource "random_password" "jwt" {
  length  = 64
  special = false
}

# Zitadel requires exactly 32 characters.
resource "random_password" "zitadel_master_key" {
  length  = 32
  special = false
}

resource "random_id" "auth_app_session_secret" {
  byte_length = 64
}

# Must be changed at first login. Meets Zitadel's default password policy.
resource "random_password" "first_admin" {
  length           = 24
  special          = true
  override_special = "!#%*-_=+"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# SSH key for the runner VMs when the customer passes none. The private half is
# kept in the vault for break-glass access.
resource "tls_private_key" "runner" {
  count     = var.runner_admin_ssh_public_key == "" ? 1 : 0
  algorithm = "ED25519"
}

locals {
  # Passwords go into URLs, so they are percent-encoded. urlencode turns a space
  # into "+", which a URL user-info part reads literally, so swap it for %20.
  db_password_url = { for k, p in random_password.db : k => replace(urlencode(p.result), "+", "%20") }

  api_server_database_url = "postgres://app_user:${local.db_password_url["api-server"]}@${local.postgres_host}:5432/app?sslmode=require"
  agents_database_url     = "postgres://agents_user:${local.db_password_url["agents"]}@${local.postgres_host}:5432/agents?sslmode=require"
  api_server_redis_url    = local.redis_enabled ? "rediss://:${replace(urlencode(local.redis_access_key), "+", "%20")}@${local.redis_host}:${local.redis_port}" : ""

  # Entry names. Which entries exist depends only on plan-time inputs, so the
  # for_each keys are known at plan time. Sensitive inputs are compared through
  # nonsensitive(): only whether they are set is used, never the value.
  vault_entry_names = concat(
    [
      "postgres-admin-password",
      "api-server-db-password",
      "agents-db-password",
      "temporal-db-password",
      "zitadel-db-password",
      "api-server-database-url",
      "agents-database-url",
      "api-server-jwt-secret",
      "zitadel-master-key",
      "auth-app-session-secret",
      "first-admin-password",
    ],
    local.redis_enabled ? ["redis-access-key", "api-server-redis-url"] : [],
    nonsensitive(var.llm_api_key != "") ? ["llm-api-key"] : [],
    nonsensitive(var.sso_client_secret != "") ? ["sso-client-secret"] : [],
    nonsensitive(var.tls_certificate != null) ? ["tls-certificate", "tls-private-key"] : [],
    var.runner_admin_ssh_public_key == "" ? ["runner-ssh-private-key"] : [],
  )

  vault_entry_values = {
    "postgres-admin-password" = local.postgres_admin_password
    "api-server-db-password"  = random_password.db["api-server"].result
    "agents-db-password"      = random_password.db["agents"].result
    "temporal-db-password"    = random_password.db["temporal"].result
    "zitadel-db-password"     = random_password.db["zitadel"].result
    "api-server-database-url" = local.api_server_database_url
    "agents-database-url"     = local.agents_database_url
    "api-server-jwt-secret"   = random_password.jwt.result
    "zitadel-master-key"      = random_password.zitadel_master_key.result
    "auth-app-session-secret" = random_id.auth_app_session_secret.hex
    "first-admin-password"    = random_password.first_admin.result
    "redis-access-key"        = local.redis_access_key
    "api-server-redis-url"    = local.api_server_redis_url
    "llm-api-key"             = var.llm_api_key
    "sso-client-secret"       = var.sso_client_secret
    "tls-certificate"         = try(var.tls_certificate.certificate, "")
    "tls-private-key"         = try(var.tls_certificate.private_key, "")
    "runner-ssh-private-key"  = try(tls_private_key.runner[0].private_key_openssh, "")
  }
}

resource "azurerm_key_vault_secret" "entry" {
  for_each     = toset(local.vault_entry_names)
  name         = each.key
  value        = local.vault_entry_values[each.key]
  key_vault_id = local.key_vault_id
  content_type = "text/plain"
  tags         = var.tags

  # The deployer must hold Key Vault Secrets Officer before it can write.
  depends_on = [
    module.keyvault,
    azurerm_role_assignment.deployer_kv,
  ]
}
