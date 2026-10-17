# Case 2a: the platform team built everything and acme's deployers may not grant
# roles. Every existing_* input is set, create_role_assignments is false, and
# traffic arrives through the platform's Istio gateway. Mirrors the eu-prod
# example in the delivery spec. Also covers a classic Azure Cache for Redis and
# the checks on brought resources.
#
# The data source defaults below describe suitable brought resources; runs that
# test a guard override one of them.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  # The platform team's resources, as the data sources read them.
  mock_data "azurerm_subnet" {
    defaults = { address_prefixes = ["10.50.4.0/22"] }
  }
  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      oidc_issuer_enabled        = true
      oidc_issuer_url            = "https://westeurope.oic.prod-aks.azure.com/66666666-7777-8888-9999-000000000000/aks-platform-weu/"
      key_vault_secrets_provider = [{ secret_rotation_enabled = false, secret_rotation_interval = "2m", secret_identity = [] }]
      kubelet_identity = [{
        client_id                 = "77777777-0000-0000-0000-000000000001"
        object_id                 = "77777777-0000-0000-0000-000000000002"
        user_assigned_identity_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/MC_rg-platform/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aks-platform-weu-agentpool"
      }]
      kube_config = [{
        host                   = "https://aks-platform-weu.hcp.westeurope.azmk8s.io:443"
        cluster_ca_certificate = "Y2EtY2VydA=="
        client_certificate     = ""
        client_key             = ""
        password               = ""
        username               = ""
      }]
    }
  }
  mock_data "azurerm_postgresql_flexible_server" {
    defaults = {
      fqdn                = "psql-platform-weu.postgres.database.azure.com"
      administrator_login = "autoheal_admin"
      version             = "16"
    }
  }
  mock_data "azurerm_managed_redis" {
    defaults = {
      hostname = "redis-platform-weu.westeurope.redis.azure.net"
      default_database = [{
        port                                          = 10000
        primary_access_key                            = "redis-key"
        secondary_access_key                          = ""
        access_keys_authentication_enabled            = true
        client_protocol                               = "Encrypted"
        clustering_policy                             = "OSSCluster"
        eviction_policy                               = "VolatileLRU"
        geo_replication_group_name                    = ""
        geo_replication_linked_database_ids           = []
        id                                            = ""
        module                                        = []
        persistence_append_only_file_backup_frequency = ""
        persistence_redis_database_backup_frequency   = ""
      }]
    }
  }
  mock_data "azurerm_redis_cache" {
    defaults = {
      hostname           = "redis-classic-weu.redis.cache.windows.net"
      ssl_port           = 6380
      primary_access_key = "redis-key"
    }
  }
  mock_data "azurerm_storage_account" {
    defaults = { is_hns_enabled = false }
  }
  mock_data "azurerm_key_vault" {
    defaults = {
      rbac_authorization_enabled = true
      tenant_id                  = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }
  }

  # OpenTofu fills computed attributes with random strings at plan time, and the
  # provider rejects them where it parses an Azure ID. These defaults give each
  # created resource a well-formed ID. Terraform keeps them unknown until apply.
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal" }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.Network/virtualNetworks/vnet-acme" }
  }
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.Network/virtualNetworks/vnet-acme/subnets/snet-acme" }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.Network/privateDnsZones/privatelink.acme.example" }
  }
  mock_resource "azurerm_storage_account" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.Storage/storageAccounts/stacme" }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme"
      vault_uri = "https://kv-acme.vault.azure.net/"
    }
  }
  mock_resource "azurerm_key_vault_key" {
    defaults = {
      id             = "https://kv-acme.vault.azure.net/keys/cmk/00000000000000000000000000000000"
      versionless_id = "https://kv-acme.vault.azure.net/keys/cmk"
    }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acme"
      principal_id = "44444444-4444-4444-4444-444444444444"
      client_id    = "55555555-5555-5555-5555-555555555555"
      tenant_id    = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "azurerm_managed_redis" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.Cache/redisEnterprise/redis-acme" }
  }
  mock_resource "azurerm_container_registry" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.ContainerRegistry/registries/cracme" }
  }
  mock_resource "azurerm_nat_gateway" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.Network/natGateways/ng-acme" }
  }
  mock_resource "azurerm_public_ip" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.Network/publicIPAddresses/pip-acme" }
  }
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-eu-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-acme" }
  }
}

mock_provider "random" {}

mock_provider "tls" {
  mock_resource "tls_private_key" {
    defaults = { public_key_openssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPdIPEGmxag1iAM9TJa938oKt9VfcpW75Ta8FpAEpXUT acme-test" }
  }
}

# With create_role_assignments = false the plan reads each workload principal's
# grants. Here an administrator has made them all at the subscription. (OpenTofu
# needs every attribute of an override object.)
override_data {
  target = data.azurerm_role_assignments.required
  values = {
    role_assignments = [
      {
        description           = "Key Vault Secrets User"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
        role_assignment_scope = "/subscriptions/66666666-7777-8888-9999-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Key Vault Secrets Officer"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
        role_assignment_scope = "/subscriptions/66666666-7777-8888-9999-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Storage Blob Data Contributor"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
        role_assignment_scope = "/subscriptions/66666666-7777-8888-9999-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "AcrPull"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
        role_assignment_scope = "/subscriptions/66666666-7777-8888-9999-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Network Contributor"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
        role_assignment_scope = "/subscriptions/66666666-7777-8888-9999-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Azure Kubernetes Service RBAC Cluster Admin"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b"
        role_assignment_scope = "/subscriptions/66666666-7777-8888-9999-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
    ]
  }
}

# The platform team's runtime vault. Its URI has no trailing slash here, to show
# that the composition adds one.
override_data {
  target = data.azurerm_key_vault.runtime_existing
  values = {
    rbac_authorization_enabled = true
    tenant_id                  = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    vault_uri                  = "https://kv-platform-weu-rt.vault.azure.net"
  }
}

variables {
  namespace        = "acme"
  environment      = "eu-prod"
  subscription_id  = "66666666-7777-8888-9999-000000000000"
  location         = "westeurope"
  autoheal_version = "1.0.0"

  existing_network = {
    aks_subnet_id      = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform-net/providers/Microsoft.Network/virtualNetworks/vnet-platform-weu/subnets/snet-aks"
    endpoint_subnet_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform-net/providers/Microsoft.Network/virtualNetworks/vnet-platform-weu/subnets/snet-pe"
    runner_subnet_id   = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform-net/providers/Microsoft.Network/virtualNetworks/vnet-platform-weu/subnets/snet-runner"
    temporal_ip        = "10.50.4.11"
  }
  existing_aks_cluster_id       = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform/providers/Microsoft.ContainerService/managedClusters/aks-platform-weu"
  existing_postgres_id          = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-platform-weu"
  existing_redis_id             = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform/providers/Microsoft.Cache/redisEnterprise/redis-platform-weu"
  existing_storage_account_id   = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform/providers/Microsoft.Storage/storageAccounts/stplatformweu"
  existing_key_vault_id         = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform/providers/Microsoft.KeyVault/vaults/kv-platform-weu"
  existing_runtime_key_vault_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform/providers/Microsoft.KeyVault/vaults/kv-platform-weu-rt"
  existing_dns_zone_id          = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform-dns/providers/Microsoft.Network/dnszones/eu.acme.example"

  create_role_assignments = false

  hostname     = "autoheal.eu.acme.example"
  edge_mode    = "istio"
  edge_address = "10.50.0.20"

  postgres_admin_password = "platform-admin-password"
  llm_api_key             = "llm-key"
}

run "everything_brought" {
  command = plan

  # The three grants the spec's example lists, in that order, and the
  # api-server grant on the runtime vault.
  assert {
    condition = output.required_role_assignments == tolist([
      "Key Vault Secrets User on kv-platform-weu for acme-eu-prod-autoheal-secrets",
      "Storage Blob Data Contributor on stplatformweu for acme-eu-prod-autoheal-api-server",
      "Key Vault Secrets Officer on kv-platform-weu-rt for acme-eu-prod-autoheal-api-server",
      "Storage Blob Data Contributor on stplatformweu for acme-eu-prod-autoheal-agents-worker",
    ])
    error_message = "required_role_assignments must list exactly the vault grant, the two storage account grants and the runtime vault grant."
  }

  assert {
    condition = (
      length(module.vnet) == 0 && length(module.aks) == 0 && length(module.postgres) == 0 &&
      length(module.redis) == 0 && length(module.blob) == 0 && length(module.keyvault) == 0 &&
      length(module.runtime_keyvault) == 0 && length(module.acr) == 0
    )
    error_message = "No brought building block may be created."
  }

  assert {
    condition = (
      length(azurerm_role_assignment.deployer_aks) == 0 && length(azurerm_role_assignment.deployer_kv) == 0 &&
      length(azurerm_role_assignment.api_server_runtime_kv) == 0
    )
    error_message = "create_role_assignments = false makes no grant."
  }

  assert {
    condition = output.autoheal_values.global.infra.runtimeSecrets == {
      kind     = "azurekeyvault"
      vaultURL = "https://kv-platform-weu-rt.vault.azure.net/"
    }
    error_message = "runtimeSecrets points at the brought runtime vault, with a trailing slash."
  }

  assert {
    condition     = !contains(keys(output.autoheal_values.global), "imageRegistry") && local.runner_image == "public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0"
    error_message = "Without a registry the chart and the runner use the public registry."
  }

  assert {
    condition     = length(terraform_data.role_assignment_check) == 1
    error_message = "The apply checks the listed grants."
  }

  assert {
    condition     = length(azurerm_storage_container.this) == 1
    error_message = "The autoheal container is created in the brought account."
  }

  assert {
    condition = output.autoheal_values.global.infra.hosts == {
      app     = "autoheal.eu.acme.example"
      auth    = "auth.autoheal.eu.acme.example"
      authApp = "auth-app.autoheal.eu.acme.example"
    }
    error_message = "hosts follow hostname."
  }

  assert {
    condition = (
      output.autoheal_values.global.infra.keyVault.name == "kv-platform-weu" &&
      output.autoheal_values.global.infra.keyVault.tenantId == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    )
    error_message = "keyVault comes from the brought vault."
  }

  assert {
    condition = (
      output.autoheal_values.global.infra.database.host == "psql-platform-weu.postgres.database.azure.com" &&
      output.autoheal_values.global.infra.database.adminUser == "autoheal_admin" &&
      output.autoheal_values.temporal.server.config.persistence.default.sql.host == "psql-platform-weu.postgres.database.azure.com" &&
      output.autoheal_values.zitadel.zitadel.configmapConfig.Database.Postgres.Host == "psql-platform-weu.postgres.database.azure.com"
    )
    error_message = "database and its copies come from the brought server."
  }

  assert {
    condition     = output.autoheal_values.global.infra.redis == { host = "redis-platform-weu.westeurope.redis.azure.net", port = 10000 }
    error_message = "redis comes from the brought Azure Managed Redis."
  }

  assert {
    condition     = output.autoheal_values.global.infra.objectStore.account == "stplatformweu"
    error_message = "objectStore.account is the brought account."
  }

  assert {
    condition = (
      output.autoheal_values.global.infra.temporal.internalIP == "10.50.4.11" &&
      !contains(keys(output.autoheal_values.global.infra), "edge")
    )
    error_message = "temporal.internalIP is the given address; no edge.internalIP in istio mode."
  }

  assert {
    condition = (
      output.autoheal_values.global.addons.install == false &&
      output.autoheal_values.global.edge.mode == "istio"
    )
    error_message = "addons.install is false for a brought cluster; edge.mode istio."
  }

  assert {
    condition = (
      output.cluster.name == "aks-platform-weu" &&
      output.cluster.resource_group == "rg-platform" &&
      output.cluster.endpoint == "https://aks-platform-weu.hcp.westeurope.azmk8s.io:443"
    )
    error_message = "cluster describes the brought cluster."
  }

  assert {
    condition     = length(module.dns) == 1 && length(output.required_dns_records) == 0
    error_message = "The three records are created in eu.acme.example, pointing at the Istio gateway."
  }

  assert {
    condition     = contains(keys(azurerm_key_vault_secret.entry), "postgres-admin-password") && contains(keys(azurerm_key_vault_secret.entry), "llm-api-key") && contains(keys(azurerm_key_vault_secret.entry), "api-server-redis-url")
    error_message = "The admin password, the LLM key and the Redis URL are written to the brought vault."
  }

  assert {
    condition = (
      output.network.vnet_id == "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform-net/providers/Microsoft.Network/virtualNetworks/vnet-platform-weu" &&
      output.network.vnet_name == "vnet-platform-weu" &&
      output.network.resource_group_name == "rg-platform-net" &&
      length(output.network.address_space) == 0 &&
      endswith(output.network.aks_subnet_id, "/vnet-platform-weu/subnets/snet-aks") &&
      endswith(output.network.runner_subnet_id, "/vnet-platform-weu/subnets/snet-runner") &&
      endswith(output.network.private_endpoint_subnet_id, "/vnet-platform-weu/subnets/snet-pe")
    )
    error_message = "network is derived from the brought subnet IDs; the VNet is not read, so address_space is empty."
  }

  assert {
    condition     = local.tool_response_callback_url == "http://10.50.4.11:8083/api/v1/internal/sandbox-tool-responses" && length(module.vnet) == 0
    error_message = "In a brought network the runner posts tool results to the brought temporal_ip, and no NSG is created."
  }

  assert {
    condition     = nonsensitive(startswith(sensitive(local.api_server_redis_url), "rediss://:") && endswith(sensitive(local.api_server_redis_url), "/0"))
    error_message = "api-server-redis-url is rediss://:<key>@<host>:<port>/0, the form in the chart's docs/secrets.md."
  }

  assert {
    condition     = length(module.pe_blob) == 0 && length(module.pe_vault) == 0 && length(module.pe_runtime_vault) == 0 && length(module.pe_redis) == 0 && length(azurerm_private_dns_zone.brought) == 0
    error_message = "No private endpoint or zone for brought resources."
  }
}

# The administrator has not made the grants yet, so the check stops the run and
# names them. On a first apply the identities do not exist before the apply, so
# the check runs during the apply, after they are created. Here the identities
# are overridden with known principal IDs so the check runs at plan.
run "missing_grants_stop_the_apply" {
  command = plan

  override_module {
    target  = module.secrets_identity
    outputs = { client_id = "c1", principal_id = "13131313-0000-0000-0000-000000000001", identity_id = "i1", name = "acme-eu-prod-autoheal-secrets", tenant_id = "t" }
  }
  override_module {
    target  = module.api_server_identity
    outputs = { client_id = "c2", principal_id = "13131313-0000-0000-0000-000000000002", identity_id = "i2", name = "acme-eu-prod-autoheal-api-server" }
  }
  override_module {
    target  = module.agents_worker_identity
    outputs = { client_id = "c3", principal_id = "13131313-0000-0000-0000-000000000003", identity_id = "i3", name = "acme-eu-prod-autoheal-agents-worker" }
  }

  override_data {
    target = data.azurerm_role_assignments.required
    values = { role_assignments = [] }
  }

  expect_failures = [terraform_data.role_assignment_check]
}

# A brought cluster with a brought registry. The kubelet grant belongs to the
# cluster owner: it is listed and checked, never made by us.
run "brought_cluster_with_registry" {
  command = plan

  variables {
    existing_acr_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform/providers/Microsoft.ContainerRegistry/registries/crplatformweu"
  }

  assert {
    condition = (
      contains(output.required_role_assignments, "AcrPull on crplatformweu for the kubelet identity of aks-platform-weu") &&
      local.kubelet_object_id == "77777777-0000-0000-0000-000000000002" &&
      length(output.required_role_assignments) == 6
    )
    error_message = "The brought cluster's kubelet AcrPull and the runner's are listed."
  }

  assert {
    condition = (
      output.autoheal_values.global.imageRegistry == "crplatformweu.azurecr.io" &&
      local.runner_image == "crplatformweu.azurecr.io/app/runner-go:chart-1.0.0"
    )
    error_message = "The chart and the runner pull from the brought registry."
  }
}

run "classic_redis" {
  command = plan

  variables {
    existing_redis_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform/providers/Microsoft.Cache/redis/redis-classic-weu"
  }

  assert {
    condition     = output.autoheal_values.global.infra.redis == { host = "redis-classic-weu.redis.cache.windows.net", port = 6380 }
    error_message = "A brought Azure Cache for Redis uses its TLS port."
  }
}

# --- Checks on brought resources -------------------------------------------------

run "access_policy_vault_is_rejected" {
  command = plan

  override_data {
    target = data.azurerm_key_vault.existing
    values = { rbac_authorization_enabled = false, tenant_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
  }

  expect_failures = [terraform_data.kv_rbac_guard]
}

run "access_policy_runtime_vault_is_rejected" {
  command = plan

  override_data {
    target = data.azurerm_key_vault.runtime_existing
    values = { rbac_authorization_enabled = false, tenant_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", vault_uri = "https://kv-platform-weu-rt.vault.azure.net/" }
  }

  expect_failures = [terraform_data.runtime_kv_rbac_guard]
}

# The runtime vault must not be the install vault: the api-server identity
# would then be able to read every install secret.
run "runtime_vault_must_differ_from_install_vault" {
  command = plan

  variables {
    existing_runtime_key_vault_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform/providers/Microsoft.KeyVault/vaults/kv-platform-weu"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "hns_storage_is_rejected" {
  command = plan

  override_data {
    target = data.azurerm_storage_account.existing
    values = { is_hns_enabled = true }
  }

  expect_failures = [terraform_data.storage_hns_guard]
}

run "old_postgres_is_rejected" {
  command = plan

  override_data {
    target = data.azurerm_postgresql_flexible_server.existing
    values = { fqdn = "psql-platform-weu.postgres.database.azure.com", administrator_login = "autoheal_admin", version = "13" }
  }

  expect_failures = [terraform_data.postgres_guard]
}

run "cluster_without_csi_addon_is_rejected" {
  command = plan

  override_data {
    target = data.azurerm_kubernetes_cluster.existing
    values = {
      oidc_issuer_enabled        = true
      oidc_issuer_url            = "https://westeurope.oic.prod-aks.azure.com/66666666-7777-8888-9999-000000000000/aks-platform-weu/"
      key_vault_secrets_provider = []
    }
  }

  expect_failures = [terraform_data.cluster_guard]
}

run "missing_admin_password" {
  command = plan

  variables {
    postgres_admin_password = ""
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "temporal_ip_outside_the_subnet" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id      = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform-net/providers/Microsoft.Network/virtualNetworks/vnet-platform-weu/subnets/snet-aks"
      endpoint_subnet_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform-net/providers/Microsoft.Network/virtualNetworks/vnet-platform-weu/subnets/snet-pe"
      runner_subnet_id   = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-platform-net/providers/Microsoft.Network/virtualNetworks/vnet-platform-weu/subnets/snet-runner"
      temporal_ip        = "10.50.9.11"
    }
  }

  expect_failures = [terraform_data.validate_addresses]
}

run "loadbalancer_needs_proxy_ip" {
  command = plan

  variables {
    edge_mode    = "loadbalancer"
    edge_address = ""
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "created_postgres_needs_its_subnet" {
  command = plan

  variables {
    existing_postgres_id = ""
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "bad_subnet_id" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id    = "snet-aks"
      runner_subnet_id = "snet-runner"
      temporal_ip      = "10.50.4.11"
    }
  }

  expect_failures = [var.existing_network]
}
