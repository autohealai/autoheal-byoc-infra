# Install secrets. Terraform writes every secret the chart reads into Secrets
# Manager as <secrets_prefix><entry> in this apply, encrypted with the secrets
# key, so the install needs no manual secret step. The entry names are the
# chart's defaults, listed in the chart's docs/secrets.md. The chart's
# secrets-sync hook Job and CronJob copy them into Kubernetes Secrets through the
# Secrets Store CSI driver with the AWS provider (global.secrets.mode =
# keyvault-csi). Nothing else is written under the prefix.
#
# Generated once and kept across upgrades: the per-service database passwords,
# the JWT signing key, the Zitadel master key, the auth session secret, the first
# admin password, the OAuth encryption and state signing keys, the tool response
# server secret, and the Aurora admin password and Redis AUTH token of the
# clusters we create. Connection strings that carry a password are rebuilt when
# the host or the password changes; the password is URL-encoded.
#
# Passed in by the customer (sensitive inputs): the admin password of a brought
# database and the AUTH token of a brought Redis, the LLM API key, the SSO client
# secret, a corporate TLS certificate and its private CA, and the GitHub App key
# and webhook secret. Each entry exists only when its input is set.
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

# api-server-go base64-decodes both OAuth keys and ignores decode errors, so
# each must be base64 of exactly 32 random bytes. The encryption key is an
# AES-256 key; a plain random string here would fail silently.
resource "random_bytes" "oauth_encryption_key" {
  length = 32
}

resource "random_bytes" "oauth_state_signing_key" {
  length = 32
}

# Used as a plain string. Letters and digits only, so it is safe in env files.
resource "random_password" "tool_response_server_secret" {
  length  = 64
  special = false
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

locals {
  # Passwords go into URLs, so they are percent-encoded. urlencode turns a space
  # into "+", which a URL user-info part reads literally, so swap it for %20.
  db_password_url = { for k, p in random_password.db : k => replace(urlencode(p.result), "+", "%20") }

  api_server_database_url = "postgres://app_user:${local.db_password_url["api-server"]}@${local.postgres_host}:5432/app?sslmode=require"
  api_server_redis_url    = local.redis_enabled ? "rediss://:${replace(urlencode(local.redis_auth_token), "+", "%20")}@${local.redis_host}:${local.redis_port}/0" : ""

  # Entry names. Which entries exist depends only on plan-time inputs, so the
  # for_each keys are known at plan time. Sensitive inputs are compared through
  # nonsensitive(): only whether they are set is used, never the value.
  secret_entry_names = concat(
    [
      "postgres-admin-password",
      "api-server-db-password",
      "agents-db-password",
      "temporal-db-password",
      "zitadel-db-password",
      "api-server-database-url",
      "api-server-jwt-secret",
      "zitadel-master-key",
      "auth-app-session-secret",
      "first-admin-password",
      "oauth-encryption-key",
      "oauth-state-signing-key",
      "tool-response-server-secret",
    ],
    local.redis_enabled ? ["redis-access-key", "api-server-redis-url"] : [],
    nonsensitive(var.llm_api_key != "") ? ["llm-api-key"] : [],
    nonsensitive(var.llm_gateway_api_key != "") ? ["gateway-api-key"] : [],
    nonsensitive(var.llm_gateway_extra_headers != "") ? ["gateway-extra-headers"] : [],
    nonsensitive(var.sso_client_secret != "") ? ["sso-client-secret"] : [],
    nonsensitive(var.tls_certificate != null) ? ["tls-certificate", "tls-private-key"] : [],
    var.edge_ca_certificate != "" ? ["edge-ca-certificate"] : [],
    nonsensitive(var.github_app_private_key != "") ? ["github-app-private-key"] : [],
    nonsensitive(var.github_app_webhook_secret != "") ? ["github-app-webhook-secret"] : [],
  )

  secret_entry_values = {
    "postgres-admin-password"     = local.postgres_admin_password
    "api-server-db-password"      = random_password.db["api-server"].result
    "agents-db-password"          = random_password.db["agents"].result
    "temporal-db-password"        = random_password.db["temporal"].result
    "zitadel-db-password"         = random_password.db["zitadel"].result
    "api-server-database-url"     = local.api_server_database_url
    "api-server-jwt-secret"       = random_password.jwt.result
    "zitadel-master-key"          = random_password.zitadel_master_key.result
    "auth-app-session-secret"     = random_id.auth_app_session_secret.hex
    "first-admin-password"        = random_password.first_admin.result
    "oauth-encryption-key"        = random_bytes.oauth_encryption_key.base64
    "oauth-state-signing-key"     = random_bytes.oauth_state_signing_key.base64
    "tool-response-server-secret" = random_password.tool_response_server_secret.result
    # ElastiCache has no access key; the chart's Redis key is the AUTH token.
    "redis-access-key"      = local.redis_auth_token
    "api-server-redis-url"  = local.api_server_redis_url
    "llm-api-key"           = var.llm_api_key
    "gateway-api-key"       = var.llm_gateway_api_key
    "gateway-extra-headers" = var.llm_gateway_extra_headers
    "sso-client-secret"     = var.sso_client_secret
    "tls-certificate"       = try(var.tls_certificate.certificate, "")
    "tls-private-key"       = try(var.tls_certificate.private_key, "")
    "edge-ca-certificate"   = var.edge_ca_certificate
    # The chart reads the GitHub App key as base64 of the PEM.
    "github-app-private-key"    = base64encode(var.github_app_private_key)
    "github-app-webhook-secret" = var.github_app_webhook_secret
  }
}

module "secrets" {
  source = "../../modules/aws/secrets-manager"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["secrets"]
  tags        = var.tags

  name_prefix             = local.secrets_prefix
  secret_names            = local.secret_entry_names
  secret_values           = local.secret_entry_values
  kms_key_arn             = local.kms_key_arns.secrets
  recovery_window_in_days = var.secrets_recovery_window_in_days
}
