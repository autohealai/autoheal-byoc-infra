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

  assert {
    condition = toset(keys(azurerm_key_vault_secret.entry)) == toset([
      "postgres-admin-password", "api-server-db-password", "agents-db-password", "temporal-db-password",
      "zitadel-db-password", "api-server-database-url", "agents-database-url", "api-server-jwt-secret",
      "zitadel-master-key", "auth-app-session-secret", "first-admin-password", "redis-access-key",
      "api-server-redis-url", "runner-ssh-private-key",
    ])
    error_message = "The default vault entries are written."
  }

  assert {
    condition     = length(module.redis) == 1 && length(module.pe_redis) == 1 && length(module.acr) == 0
    error_message = "Redis and its private endpoint are created; no registry by default."
  }
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
  }

  assert {
    condition     = output.autoheal_values.global.infra.hosts.auth == "login.acme.example" && output.autoheal_values.global.infra.hosts.authApp == "login-app.acme.example"
    error_message = "auth_hostname and auth_app_hostname override the defaults."
  }

  assert {
    condition     = length(output.required_role_assignments) == 8
    error_message = "A created cluster, vault and registry with create_role_assignments = false lists all eight grants."
  }
}

# --- Input checks --------------------------------------------------------------

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
