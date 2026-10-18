# Case 1: we build everything. Runs a real plan against mocked providers, so no
# subscription is touched. Covers the hand-off values, the reserved addresses,
# each edge mode, the DNS records and their listing, and the input checks that
# apply when everything is created.
#
# Under a mocked provider, data sources return the defaults below as known values
# and created resources have unknown computed attributes at plan time, so the
# assertions use values the plan knows: inputs, names and computed addresses.
# module.aks is overridden because the mock returns its kubelet_identity and
# kube_config blocks empty, which the module indexes into.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  # OpenTofu fills computed attributes with random strings at plan time, and the
  # provider rejects them where it parses an Azure ID. These defaults give each
  # created resource a well-formed ID. Terraform keeps them unknown until apply.
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal" }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/vnet-acme" }
  }
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/vnet-acme/subnets/snet-acme" }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/privateDnsZones/privatelink.acme.example" }
  }
  mock_resource "azurerm_storage_account" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Storage/storageAccounts/stacme" }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme"
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
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acme"
      principal_id = "44444444-4444-4444-4444-444444444444"
      client_id    = "55555555-5555-5555-5555-555555555555"
      tenant_id    = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "azurerm_managed_redis" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Cache/redisEnterprise/redis-acme" }
  }
  mock_resource "azurerm_container_registry" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ContainerRegistry/registries/cracme" }
  }
  mock_resource "azurerm_nat_gateway" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/natGateways/ng-acme" }
  }
  mock_resource "azurerm_public_ip" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/publicIPAddresses/pip-acme" }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/networkSecurityGroups/nsg-acme" }
  }
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-acme" }
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
        role_assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Key Vault Secrets Officer"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
        role_assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Storage Blob Data Contributor"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
        role_assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "AcrPull"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
        role_assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Network Contributor"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
        role_assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Azure Kubernetes Service RBAC Cluster Admin"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b"
        role_assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
    ]
  }
}

override_module {
  target = module.aks
  outputs = {
    cluster_name               = "acme-prod-autoheal"
    cluster_id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ContainerService/managedClusters/acme-prod-autoheal"
    oidc_issuer_url            = "https://oidc.prod-aks.azure.example/00000000-0000-0000-0000-000000000000/"
    kubelet_identity_object_id = "22222222-2222-2222-2222-222222222222"
    identity_principal_id      = "33333333-3333-3333-3333-333333333333"
    identity_name              = "acme-prod-autoheal-uami"
    node_resource_group        = "MC_rg-acme-prod-autoheal"
    host                       = "https://acme-prod-autoheal.hcp.centralus.azmk8s.io:443"
    cluster_ca_certificate     = "Y2EtY2VydA=="
  }
}

variables {
  namespace            = "acme"
  environment          = "prod"
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  location             = "centralus"
  hostname             = "autoheal.acme.example"
  autoheal_version     = "1.0.0"
  existing_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"
  deployer_ip_ranges   = ["203.0.113.10"]

  private_endpoints_enabled = true
}

# Defaults: loadbalancer mode in a network we create.
run "loadbalancer_defaults" {
  command = plan

  assert {
    condition     = output.autoheal_values.global.infra.version == "2.0.0" && output.autoheal_values.global.infra.cloud == "azure"
    error_message = "global.infra.version must be 2.0.0 and cloud azure."
  }

  assert {
    condition = output.autoheal_values.global.infra.hosts == {
      app     = "autoheal.acme.example"
      auth    = "auth.autoheal.acme.example"
      authApp = "auth-app.autoheal.acme.example"
    }
    error_message = "hosts must default auth and authApp to auth.<hostname> and auth-app.<hostname>."
  }

  # The AKS subnet of 10.60.0.0/16 is 10.60.0.0/20; Azure keeps .255, so the
  # proxy takes .254 and Temporal .253.
  assert {
    condition     = output.autoheal_values.global.infra.temporal.internalIP == "10.60.15.253"
    error_message = "temporal.internalIP must be the third address from the end of the AKS subnet."
  }

  assert {
    condition     = output.autoheal_values.global.infra.edge.internalIP == "10.60.15.254"
    error_message = "edge.internalIP must be the second address from the end of the AKS subnet in loadbalancer mode."
  }

  assert {
    condition     = local.temporal_ip == "10.60.15.253"
    error_message = "The runner must connect to the reserved Temporal address."
  }

  assert {
    condition = (
      output.autoheal_values.global.infra.database.port == 5432 &&
      output.autoheal_values.global.infra.database.adminUser == "pgadmin" &&
      output.autoheal_values.global.infra.database.adminPasswordVaultEntry == "postgres-admin-password"
    )
    error_message = "database must carry port 5432, the admin login and the admin password vault entry name."
  }

  assert {
    condition = (
      output.autoheal_values.global.infra.objectStore.kind == "azure-blob" &&
      output.autoheal_values.global.infra.objectStore.container == "autoheal"
    )
    error_message = "objectStore must be azure-blob with the autoheal container."
  }

  assert {
    condition = (
      output.autoheal_values.global.addons.install == true &&
      output.autoheal_values.global.secrets.mode == "keyvault-csi" &&
      output.autoheal_values.global.edge.mode == "loadbalancer"
    )
    error_message = "Suggestions: addons.install true for a created cluster, keyvault-csi, edge mode from edge_mode."
  }

  assert {
    condition     = output.autoheal_values.zitadel.zitadel.configmapConfig.ExternalDomain == "auth.autoheal.acme.example"
    error_message = "The Zitadel ExternalDomain copy must equal hosts.auth."
  }

  assert {
    condition     = contains(keys(output.autoheal_values.global.infra), "redis")
    error_message = "Redis is on by default, so global.infra.redis must be present."
  }

  assert {
    condition     = output.cluster.cloud == "azure" && output.cluster.name == "acme-prod-autoheal" && output.cluster.resource_group == "rg-acme-prod-autoheal"
    error_message = "cluster must name the created cluster and its resource group."
  }

  assert {
    condition     = output.cluster.endpoint == "https://acme-prod-autoheal.hcp.centralus.azmk8s.io:443" && output.cluster.ca_certificate == "Y2EtY2VydA=="
    error_message = "cluster must carry the endpoint and CA certificate."
  }

  assert {
    condition     = length(output.required_role_assignments) == 0 && length(output.required_dns_records) == 0
    error_message = "Nothing is listed when we make the grants and the records."
  }

  assert {
    condition = (
      length(module.dns) == 1 &&
      module.dns[0].fqdns != null
    )
    error_message = "The three records are created in the zone."
  }

  # The chart's default entry names (docs/secrets.md in the chart). The
  # generated runner SSH key is not among them: it stays in the state.
  assert {
    condition = toset(keys(azurerm_key_vault_secret.entry)) == toset([
      "postgres-admin-password", "api-server-db-password", "agents-db-password", "temporal-db-password",
      "zitadel-db-password", "api-server-database-url", "api-server-jwt-secret", "zitadel-master-key",
      "auth-app-session-secret", "first-admin-password", "oauth-encryption-key", "oauth-state-signing-key",
      "tool-response-server-secret", "redis-access-key", "api-server-redis-url",
    ])
    error_message = "The default vault entries are written."
  }

  assert {
    condition     = random_bytes.oauth_encryption_key.length == 32 && random_bytes.oauth_state_signing_key.length == 32
    error_message = "oauth-encryption-key and oauth-state-signing-key must each be 32 random bytes."
  }

  assert {
    condition     = random_password.tool_response_server_secret.length >= 48 && !random_password.tool_response_server_secret.special
    error_message = "The tool response secret must be 48+ letters and digits."
  }

  # Only the chart's hook service account reads the vault.
  assert {
    condition     = tolist(var.service_accounts.secrets) == tolist(["autoheal-hooks"]) && var.service_accounts.namespace == "autoheal"
    error_message = "By default the secrets identity is federated to autoheal-hooks in namespace autoheal only."
  }

  assert {
    condition     = !contains(keys(output.autoheal_values.global.edge), "tls")
    error_message = "No CA entry is suggested without edge_ca_certificate."
  }

  assert {
    condition     = !contains(keys(output.autoheal_values.global), "llm")
    error_message = "Nothing under global.llm is suggested without llm_gateway_extra_headers."
  }

  assert {
    condition = (
      tolist(output.network.address_space) == tolist(["10.60.0.0/16"]) &&
      output.network.resource_group_name == "rg-acme-prod-autoheal" &&
      output.network.vnet_name == module.vnet[0].vnet_name
    )
    error_message = "network describes the VNet we create and its address space."
  }

  assert {
    condition     = local.runner_image == "public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0" && !local.runner_uses_acr
    error_message = "Without a registry the runner pulls app/runner-go:chart-<autoheal_version> from the public registry, with no ACR login."
  }

  # Without a registry no image key is suggested, so the chart's default public
  # registry applies.
  assert {
    condition = (
      !contains(keys(output.autoheal_values.global), "imageRegistry") &&
      !contains(keys(output.autoheal_values.temporal.server), "image") &&
      !contains(keys(output.autoheal_values.temporal), "web") &&
      !contains(keys(output.autoheal_values.temporal), "admintools") &&
      !contains(keys(output.autoheal_values.zitadel), "image") &&
      !contains(keys(output.autoheal_values.zitadel), "login") &&
      !contains(keys(output.autoheal_values.zitadel), "imageRegistry")
    )
    error_message = "No imageRegistry or image copies without a registry."
  }

  # The runtime vault: a second vault, named after the install vault with -rt,
  # with its own private endpoint and the api-server grant.
  assert {
    condition = (
      length(module.runtime_keyvault) == 1 &&
      module.runtime_keyvault[0].key_vault_name == "acme-prod-autoheal-rt" &&
      length(module.pe_runtime_vault) == 1 &&
      length(azurerm_role_assignment.api_server_runtime_kv) == 1
    )
    error_message = "The runtime vault, its private endpoint and the api-server Key Vault Secrets Officer grant are created."
  }

  assert {
    condition     = output.autoheal_values.global.infra.runtimeSecrets.kind == "azurekeyvault"
    error_message = "global.infra.runtimeSecrets.kind must be azurekeyvault."
  }

  assert {
    condition     = local.runtime_key_vault_purge_protection_enabled == false
    error_message = "The runtime vault follows the install vault's purge protection, off by default."
  }

  assert {
    condition     = local.tool_response_callback_url == "http://10.60.15.253:8083/api/v1/internal/sandbox-tool-responses"
    error_message = "The runner posts tool results to the api-server-go internal listener on the Temporal address."
  }

  assert {
    condition     = module.vnet[0].aks_nsg_name == "${module.vnet[0].vnet_name}-aks-nsg"
    error_message = "A network we create gets the AKS subnet NSG for the Temporal address."
  }

  assert {
    condition     = length(module.redis) == 1 && length(module.pe_redis) == 1 && length(module.acr) == 0
    error_message = "Redis and its private endpoint are created; no registry by default."
  }
}

# Optional entries the chart reads when they are configured: the private CA of
# the edge certificate, the GitHub App credentials and the LLM gateway.
run "optional_vault_entries" {
  command = plan

  variables {
    tls_certificate = {
      certificate = "-----BEGIN CERTIFICATE-----\nleaf\n-----END CERTIFICATE-----\n"
      private_key = "-----BEGIN PRIVATE KEY-----\nkey\n-----END PRIVATE KEY-----\n"
    }
    edge_ca_certificate       = "-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----\n"
    github_app_private_key    = "-----BEGIN RSA PRIVATE KEY-----\napp\n-----END RSA PRIVATE KEY-----\n"
    github_app_webhook_secret = "webhook"
    llm_api_key               = "llm"
    sso_client_secret         = "sso"
    llm_gateway_api_key       = "gateway"
    llm_gateway_extra_headers = "{\"x-portkey-config\":\"{\\\"retry\\\":{\\\"attempts\\\":2}}\"}"
  }

  assert {
    condition = alltrue([
      for e in ["tls-certificate", "tls-private-key", "edge-ca-certificate", "github-app-private-key", "github-app-webhook-secret", "llm-api-key", "sso-client-secret", "gateway-api-key", "gateway-extra-headers"] :
      contains(keys(azurerm_key_vault_secret.entry), e)
    ])
    error_message = "Each optional entry is written when its input is set."
  }

  assert {
    condition     = nonsensitive(azurerm_key_vault_secret.entry["github-app-private-key"].value) == base64encode("-----BEGIN RSA PRIVATE KEY-----\napp\n-----END RSA PRIVATE KEY-----\n")
    error_message = "The GitHub App key is stored as base64 of the PEM, the form the chart reads."
  }

  assert {
    condition     = output.autoheal_values.global.edge.tls.caVaultEntry == "edge-ca-certificate"
    error_message = "global.edge.tls.caVaultEntry is suggested when edge_ca_certificate is set."
  }

  assert {
    condition     = output.autoheal_values.global.llm == { gateway = { extraHeadersVaultEntry = "gateway-extra-headers" } }
    error_message = "Only global.llm.gateway.extraHeadersVaultEntry is suggested when llm_gateway_extra_headers is set."
  }
}

# The gateway headers must be a JSON object of strings, as agents-py reads them.
run "gateway_headers_must_be_json" {
  command = plan

  variables {
    llm_gateway_extra_headers = "x-portkey-config: {}"
  }

  expect_failures = [var.llm_gateway_extra_headers]
}

run "gateway_headers_must_be_an_object" {
  command = plan

  variables {
    llm_gateway_extra_headers = "[\"x-portkey-config\"]"
  }

  expect_failures = [var.llm_gateway_extra_headers]
}

run "gateway_header_values_must_be_strings" {
  command = plan

  variables {
    llm_gateway_extra_headers = "{\"x-portkey-config\":{\"retry\":{\"attempts\":2}}}"
  }

  expect_failures = [var.llm_gateway_extra_headers]
}

run "github_key_must_be_pem" {
  command = plan

  variables {
    github_app_private_key = "LS0tLS1CRUdJTg=="
  }

  expect_failures = [var.github_app_private_key]
}

run "gateway_api_with_edge_address" {
  command = plan

  variables {
    edge_mode    = "gateway-api"
    edge_address = "10.60.0.40"
  }

  assert {
    condition     = !contains(keys(output.autoheal_values.global.infra), "edge")
    error_message = "global.infra.edge is set only in loadbalancer mode."
  }

  assert {
    condition     = output.autoheal_values.global.edge.mode == "gateway-api"
    error_message = "global.edge.mode must follow edge_mode."
  }

  assert {
    condition     = length(output.required_dns_records) == 0 && length(module.dns) == 1
    error_message = "With edge_address set the records are created."
  }
}

run "istio_with_edge_address" {
  command = plan

  variables {
    edge_mode    = "istio"
    edge_address = "10.60.0.41"
  }

  assert {
    condition     = output.autoheal_values.global.edge.mode == "istio" && !contains(keys(output.autoheal_values.global.infra), "edge")
    error_message = "istio mode: edge.mode istio and no global.infra.edge."
  }
}

# No edge_address yet: the records cannot be created, so they are listed with a
# placeholder value.
run "ingress_without_edge_address" {
  command = plan

  variables {
    edge_mode = "ingress"
  }

  assert {
    condition     = length(module.dns) == 0 && length(output.required_dns_records) == 3
    error_message = "Without an address the records are listed, not created."
  }

  assert {
    condition     = output.required_dns_records[1].name == "auth.autoheal.acme.example" && output.required_dns_records[1].type == "A"
    error_message = "required_dns_records lists app, auth and authApp as A records."
  }
}

run "none_mode" {
  command = plan

  variables {
    edge_mode = "none"
  }

  assert {
    condition     = output.autoheal_values.global.edge.mode == "none" && length(module.dns) == 0
    error_message = "none mode: no records without an address."
  }
}

# DNS kept outside the cloud account: no zone is needed and the records are
# listed with the reserved proxy address.
run "dns_records_off_without_zone" {
  command = plan

  variables {
    create_dns_records   = false
    existing_dns_zone_id = ""
  }

  assert {
    condition     = length(module.dns) == 0
    error_message = "No records are created with create_dns_records = false."
  }

  assert {
    condition = (
      [for r in output.required_dns_records : r.name] == ["autoheal.acme.example", "auth.autoheal.acme.example", "auth-app.autoheal.acme.example"] &&
      alltrue([for r in output.required_dns_records : r.type == "A" && r.value == "10.60.15.254"])
    )
    error_message = "required_dns_records lists the three hostnames pointing at the proxy address."
  }
}

run "redis_off" {
  command = plan

  variables {
    redis_enabled = false
  }

  assert {
    condition     = !contains(keys(output.autoheal_values.global.infra), "redis") && length(module.redis) == 0
    error_message = "redis_enabled = false drops Redis and global.infra.redis."
  }

  assert {
    condition     = !contains(keys(azurerm_key_vault_secret.entry), "api-server-redis-url")
    error_message = "No Redis URL entry without Redis."
  }
}

run "custom_hostnames_and_registry" {
  command = plan

  variables {
    auth_hostname           = "login.acme.example"
    auth_app_hostname       = "login-app.acme.example"
    create_registry         = true
    create_role_assignments = false
    runner_image_tag        = "test-1"
  }

  # The registry we create is acmeprodautoheal.azurecr.io.
  assert {
    condition     = local.runner_image == "acmeprodautoheal.azurecr.io/app/runner-go:test-1" && local.runner_uses_acr
    error_message = "With a registry the runner pulls app/runner-go from it and logs in to it; runner_image_tag overrides the tag."
  }

  assert {
    condition = (
      output.autoheal_values.global.imageRegistry == "acmeprodautoheal.azurecr.io" &&
      output.autoheal_values.temporal.server.image.repository == "acmeprodautoheal.azurecr.io/external/temporal-server" &&
      output.autoheal_values.temporal.web.image.repository == "acmeprodautoheal.azurecr.io/external/temporal-ui" &&
      output.autoheal_values.temporal.admintools.image.repository == "acmeprodautoheal.azurecr.io/external/temporal-admin-tools" &&
      output.autoheal_values.zitadel.image.repository == "acmeprodautoheal.azurecr.io/external/zitadel" &&
      output.autoheal_values.zitadel.login.image.repository == "acmeprodautoheal.azurecr.io/external/zitadel-login" &&
      output.autoheal_values.zitadel.imageRegistry == "acmeprodautoheal.azurecr.io"
    )
    error_message = "With a registry, global.imageRegistry and the Temporal and Zitadel image copies point at it."
  }

  # The image copies sit next to the database and hostname copies.
  assert {
    condition = (
      contains(keys(output.autoheal_values.temporal.server.config.persistence), "default") &&
      output.autoheal_values.zitadel.zitadel.configmapConfig.ExternalDomain == "login.acme.example"
    )
    error_message = "The persistence and configmapConfig copies are kept alongside the image copies."
  }

  assert {
    condition     = output.autoheal_values.global.infra.hosts.auth == "login.acme.example" && output.autoheal_values.global.infra.hosts.authApp == "login-app.acme.example"
    error_message = "auth_hostname and auth_app_hostname override the defaults."
  }

  assert {
    condition     = length(output.required_role_assignments) == 9
    error_message = "A created cluster, vault and registry with create_role_assignments = false lists all nine grants."
  }

  assert {
    condition = (
      contains(output.required_role_assignments, "Key Vault Secrets Officer on acme-prod-autoheal-rt for acme-prod-autoheal-api-server") &&
      contains(output.required_role_assignments, "AcrPull on acmeprodautoheal for the kubelet identity of acme-prod-autoheal")
    )
    error_message = "The api-server grant on the runtime vault and the kubelet's AcrPull are listed."
  }

  # The cluster identity creates the internal load balancers on the pinned
  # addresses, so its network grant is listed too.
  assert {
    condition = length([
      for l in output.required_role_assignments : l
      if startswith(l, "Network Contributor on ") && endswith(l, " for acme-prod-autoheal-uami")
    ]) == 1
    error_message = "The cluster identity's Network Contributor grant on the VNet must be listed."
  }
}

# A brought registry is used the same way as one we create.
run "existing_registry" {
  command = plan

  variables {
    existing_acr_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.ContainerRegistry/registries/crMirror"
  }

  assert {
    condition = (
      length(module.acr) == 0 &&
      output.autoheal_values.global.imageRegistry == "crmirror.azurecr.io" &&
      output.autoheal_values.zitadel.imageRegistry == "crmirror.azurecr.io" &&
      local.runner_image == "crmirror.azurecr.io/app/runner-go:chart-1.0.0" &&
      local.runner_uses_acr
    )
    error_message = "A brought registry sets global.imageRegistry, the copies and the runner image from its login server."
  }
}

# runner_image_repository wins over the computed default. A repository outside
# the registry needs no ACR login.
run "runner_image_override" {
  command = plan

  variables {
    create_registry         = true
    runner_image_repository = "mirror.acme.example/autoheal/runner-go"
  }

  assert {
    condition     = local.runner_image == "mirror.acme.example/autoheal/runner-go:chart-1.0.0" && !local.runner_uses_acr
    error_message = "runner_image_repository overrides the runner image; no ACR login for another registry."
  }
}

# A long label id: both vault names stay within 24 characters and differ.
run "long_name_runtime_vault" {
  command = plan

  variables {
    namespace   = "acmecorporation"
    environment = "production"
  }

  assert {
    condition = (
      module.runtime_keyvault[0].key_vault_name == "acmecorporation-produ-rt" &&
      module.keyvault[0].key_vault_name == "acmecorporation-producti"
    )
    error_message = "The runtime vault name is the label id cut to 21 characters plus -rt."
  }
}

run "runtime_vault_purge_protection" {
  command = plan

  variables {
    key_vault_purge_protection_enabled = true
  }

  assert {
    condition     = local.runtime_key_vault_purge_protection_enabled == true
    error_message = "The runtime vault takes the install vault's purge protection when its own input is null."
  }
}

run "runtime_vault_purge_protection_override" {
  command = plan

  variables {
    key_vault_purge_protection_enabled         = true
    runtime_key_vault_purge_protection_enabled = false
  }

  assert {
    condition     = local.runtime_key_vault_purge_protection_enabled == false
    error_message = "runtime_key_vault_purge_protection_enabled overrides the install vault's setting."
  }
}

# --- Input checks --------------------------------------------------------------

run "bad_runtime_retention" {
  command = plan

  variables {
    runtime_key_vault_soft_delete_retention_days = 120
  }

  expect_failures = [var.runtime_key_vault_soft_delete_retention_days]
}

run "records_need_a_zone" {
  command = plan

  variables {
    existing_dns_zone_id = ""
  }

  expect_failures = [terraform_data.validate_dns]
}

run "hosts_must_be_in_the_zone" {
  command = plan

  variables {
    auth_hostname = "auth.other.example"
  }

  expect_failures = [terraform_data.validate_dns]
}

run "cmk_needs_role_assignments" {
  command = plan

  variables {
    cmk_enabled                        = true
    key_vault_purge_protection_enabled = true
    create_role_assignments            = false
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "brought_cluster_needs_a_network" {
  command = plan

  # A suitable cluster, so only the missing network fails.
  override_data {
    target = data.azurerm_kubernetes_cluster.existing
    values = {
      oidc_issuer_enabled        = true
      key_vault_secrets_provider = [{ secret_rotation_enabled = false, secret_rotation_interval = "2m", secret_identity = [] }]
    }
  }

  variables {
    existing_aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.ContainerService/managedClusters/aks-platform"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "bad_edge_mode" {
  command = plan

  variables {
    edge_mode = "nodeport"
  }

  expect_failures = [var.edge_mode]
}

run "bad_version" {
  command = plan

  variables {
    autoheal_version = "latest"
  }

  expect_failures = [var.autoheal_version]
}
