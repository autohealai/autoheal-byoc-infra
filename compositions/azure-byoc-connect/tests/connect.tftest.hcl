# Plan-level smoke + output-contract guard for the connect composition. `terraform
# validate` (the CI static gate) type-checks but never runs a plan; this does, against
# fully mocked azurerm data sources, so no subscription is touched. It proves the whole
# composition (app identity + the dedicated ESO identity + optional secret seeding) is
# internally consistent and that the shared output contract the installer reads stays
# intact — the drift that previously made connect-mode installs unusable (no ESO
# identity / missing eso_identity_* outputs) would fail this test.
#
# Mocked data sources return the `defaults` below as KNOWN values, so every output
# derived from the existing resources is known at plan time and can be asserted. The
# identities this composition creates return computed-unknown ids under the mock, which
# is fine for a plan.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      name            = "aks-customer-autoheal"
      oidc_issuer_url = "https://oidc.prod-aks.azure.example/00000000-0000-0000-0000-000000000000/"
      kube_config = [{
        host = "https://aks-customer-autoheal.hcp.centralus.azmk8s.io:443"
      }]
    }
  }

  mock_data "azurerm_postgresql_flexible_server" {
    defaults = {
      fqdn = "pg-customer-autoheal.postgres.database.azure.com"
    }
  }

  mock_data "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-customer-autoheal/providers/Microsoft.KeyVault/vaults/kv-customer-autoheal"
      vault_uri = "https://kv-customer-autoheal.vault.azure.net/"
      # RBAC-mode vault: satisfies the kv_rbac_guard precondition. The
      # access-policy-vault rejection is asserted in refuses_access_policy_vault below.
      rbac_authorization_enabled = true
    }
  }

  mock_data "azurerm_redis_cache" {
    defaults = {
      hostname           = "redis-customer-autoheal.redis.cache.windows.net"
      ssl_port           = 6380
      primary_access_key = "mock-redis-key" # pragma: allowlist secret
    }
  }

  mock_data "azurerm_container_registry" {
    defaults = {
      login_server = "crcustomerautoheal.azurecr.io"
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-customer-autoheal/providers/Microsoft.ContainerRegistry/registries/crcustomerautoheal"
    }
  }

  mock_data "azurerm_storage_account" {
    defaults = {
      name                  = "stcustomerautoheal"
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-customer-autoheal/providers/Microsoft.Storage/storageAccounts/stcustomerautoheal"
      primary_blob_endpoint = "https://stcustomerautoheal.blob.core.windows.net/"
      is_hns_enabled        = false
    }
  }
}

variables {
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  location             = "centralus"
  resource_group_name  = "rg-customer-autoheal"
  aks_cluster_name     = "aks-customer-autoheal"
  postgres_server_name = "pg-customer-autoheal"
  key_vault_name       = "kv-customer-autoheal"
  redis_cache_name     = "redis-customer-autoheal"
  acr_name             = "crcustomerautoheal"
  storage_account_name = "stcustomerautoheal"
  namespace            = "acme"
  environment          = "prod"
}

# Default posture: seed secrets on. The plan must succeed (the deployer Secrets Officer
# grant + the five seed secrets + both identities all resolve), and the shared output
# contract read from the existing resources must match the mocked inputs.
run "plans_and_emits_contract" {
  command = plan

  assert {
    condition     = output.secret_store_uri == "https://kv-customer-autoheal.vault.azure.net/"
    error_message = "secret_store_uri must be the existing Key Vault URI (ESO ClusterSecretStore target)."
  }

  assert {
    condition     = output.redis_endpoint == "redis-customer-autoheal.redis.cache.windows.net:6380"
    error_message = "redis_endpoint must be host:ssl_port of the existing managed Redis."
  }

  assert {
    condition     = output.object_store == "stcustomerautoheal/attachments"
    error_message = "object_store must be <existing storage account>/<container>."
  }

  assert {
    condition     = output.blob_endpoint == "https://stcustomerautoheal.blob.core.windows.net/"
    error_message = "blob_endpoint must be the existing account's primary blob endpoint (the installer's GIT_REGISTRY_AZURE_STORAGE_ACCOUNT_URL)."
  }

  assert {
    condition     = output.postgres_host == "pg-customer-autoheal.postgres.database.azure.com"
    error_message = "postgres_host must be the existing PostgreSQL Flexible Server FQDN."
  }

  assert {
    condition     = output.oidc_issuer_url == "https://oidc.prod-aks.azure.example/00000000-0000-0000-0000-000000000000/"
    error_message = "oidc_issuer_url must come from the existing cluster."
  }

  assert {
    condition     = output.eso_service_account == "external-secrets/external-secrets"
    error_message = "eso_service_account must be the federated ESO controller SA the installer wires into the ClusterSecretStore."
  }

  # Default seeding derives exactly the five data-tier secrets (redis-host/-port/
  # -password, postgres-host/-user) and grants the deployer Secrets Officer to write
  # them into the existing vault.
  assert {
    condition     = length(azurerm_key_vault_secret.seed) == 5
    error_message = "Default seeding must write the five derived data-tier secrets into the existing Key Vault."
  }

  assert {
    condition     = length(azurerm_role_assignment.deployer_kv) == 1
    error_message = "Seeding must grant the deployer Key Vault Secrets Officer on the existing vault."
  }
}

# With seeding off, the composition touches no secrets and makes no deployer grant — it
# only binds the app + ESO identities to the customer-managed vault. The plan must still
# succeed (proves the seed path is cleanly optional for customers who manage secrets).
run "plans_with_seeding_off" {
  command = plan

  variables {
    seed_secrets_enabled = false
    grant_app_acr_pull   = true
  }

  assert {
    condition     = length(azurerm_key_vault_secret.seed) == 0
    error_message = "seed_secrets_enabled=false must write no secrets."
  }

  assert {
    condition     = length(azurerm_role_assignment.deployer_kv) == 0
    error_message = "seed_secrets_enabled=false must not grant the deployer Secrets Officer."
  }

  # The ESO identity (and its outputs) exist regardless of seeding — the installer always
  # needs them to wire the ClusterSecretStore.
  assert {
    condition     = output.eso_service_account == "external-secrets/external-secrets"
    error_message = "eso_service_account output must exist even with seeding off."
  }
}

# The identities' client_ids are computed (unknown at plan) and mock_provider can't mint a
# parseable ARM id for them (apply then fails parsing parent_id on the federated creds), so
# override BOTH user-assigned identities with valid, DISTINCT ids/client_ids. This proves
# the installer-facing outputs are wired to the right module: eso_identity_client_id must
# resolve from module.eso_identity and runner_identity from module.workload_identity — if
# either output pointed at the wrong module both would collapse to the same value and the
# distinctness assert would fail. (That the app identity holds no Key Vault role is enforced
# one level down in modules/azure/workload-identity by kv_role_enabled = false.)
#
# This run must `apply`: the client_id outputs are computed, so they stay unknown under a
# plan even with the overrides. The overrides supply valid ARM ids so the federated-credential
# parent_id parses (a bare mock id does not), letting the apply — and teardown — complete.
run "wires_distinct_app_and_eso_identity_outputs" {
  command = apply

  override_resource {
    target = module.workload_identity.azurerm_user_assigned_identity.app
    values = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-customer-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-autoheal-app"
      client_id    = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      principal_id = "aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa"
      tenant_id    = "00000000-0000-0000-0000-000000000000"
    }
  }

  override_resource {
    target = module.eso_identity.azurerm_user_assigned_identity.eso
    values = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-customer-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-autoheal-eso"
      client_id    = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
      principal_id = "bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb"
      tenant_id    = "00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = output.eso_identity_client_id != output.runner_identity
    error_message = "The ESO identity and the app identity must be separate principals (only ESO holds Key Vault access); their client-id outputs must not resolve from the same module."
  }

  assert {
    condition     = output.eso_identity_client_id == "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" && output.runner_identity == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    error_message = "eso_identity_client_id must come from module.eso_identity and runner_identity from module.workload_identity."
  }

  assert {
    condition     = output.eso_tenant_id != ""
    error_message = "eso_tenant_id must be populated for the installer to configure the ClusterSecretStore."
  }
}

# The RBAC guard must REJECT an access-policy vault. Override just the Key Vault data source
# to enable_rbac_authorization = false (everything else stays valid); the plan must stop at
# the kv_rbac_guard precondition rather than ship role assignments that grant nothing.
run "refuses_access_policy_vault" {
  command = plan

  override_data {
    target = data.azurerm_key_vault.existing
    values = {
      id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-customer-autoheal/providers/Microsoft.KeyVault/vaults/kv-customer-autoheal"
      vault_uri                  = "https://kv-customer-autoheal.vault.azure.net/"
      rbac_authorization_enabled = false
    }
  }

  expect_failures = [
    terraform_data.kv_rbac_guard,
  ]
}

# The HNS guard must REJECT an ADLS Gen2 account. Override just the storage account data
# source to is_hns_enabled = true; the plan must stop at the storage_hns_guard
# precondition rather than ship an install whose Git Registry renames misbehave.
run "refuses_hns_storage_account" {
  command = plan

  override_data {
    target = data.azurerm_storage_account.existing
    values = {
      name                  = "stcustomerautoheal"
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-customer-autoheal/providers/Microsoft.Storage/storageAccounts/stcustomerautoheal"
      primary_blob_endpoint = "https://stcustomerautoheal.blob.core.windows.net/"
      is_hns_enabled        = true
    }
  }

  expect_failures = [
    terraform_data.storage_hns_guard,
  ]
}
