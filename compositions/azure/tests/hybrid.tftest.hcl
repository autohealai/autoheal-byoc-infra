# Case 3: acme brings its network and DNS zone; we create everything else. This
# is the prod example in the delivery spec: the cluster, Postgres, Redis, storage
# and vault are created in acme's subnets, and the reserved Temporal and proxy
# addresses come from acme's network team.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  # acme's network: the AKS subnet the reserved addresses must sit in.
  mock_data "azurerm_subnet" {
    defaults = { address_prefixes = ["10.20.4.0/22"] }
  }

  # OpenTofu fills computed attributes with random strings at plan time, and the
  # provider rejects them where it parses an Azure ID. These defaults give each
  # created resource a well-formed ID. Terraform keeps them unknown until apply.
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal" }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/vnet-acme" }
  }
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/vnet-acme/subnets/snet-acme" }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/privateDnsZones/privatelink.acme.example" }
  }
  mock_resource "azurerm_storage_account" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Storage/storageAccounts/stacme" }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme"
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
      id           = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acme"
      principal_id = "44444444-4444-4444-4444-444444444444"
      client_id    = "55555555-5555-5555-5555-555555555555"
      tenant_id    = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "azurerm_managed_redis" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Cache/redisEnterprise/redis-acme" }
  }
  mock_resource "azurerm_container_registry" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ContainerRegistry/registries/cracme" }
  }
  mock_resource "azurerm_nat_gateway" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/natGateways/ng-acme" }
  }
  mock_resource "azurerm_public_ip" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/publicIPAddresses/pip-acme" }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/networkSecurityGroups/nsg-acme" }
  }
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-acme" }
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
        role_assignment_scope = "/subscriptions/11111111-2222-3333-4444-555555555555"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Key Vault Secrets Officer"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
        role_assignment_scope = "/subscriptions/11111111-2222-3333-4444-555555555555"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Storage Blob Data Contributor"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
        role_assignment_scope = "/subscriptions/11111111-2222-3333-4444-555555555555"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "AcrPull"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
        role_assignment_scope = "/subscriptions/11111111-2222-3333-4444-555555555555"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Network Contributor"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
        role_assignment_scope = "/subscriptions/11111111-2222-3333-4444-555555555555"
        role_assignment_id    = "", role_assignment_name = "", principal_id = "", principal_type = ""
        condition             = "", condition_version = "", delegated_managed_identity_resource_id = ""
      },
      {
        description           = "Azure Kubernetes Service RBAC Cluster Admin"
        role_definition_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b"
        role_assignment_scope = "/subscriptions/11111111-2222-3333-4444-555555555555"
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
    cluster_id                 = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ContainerService/managedClusters/acme-prod-autoheal"
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
  namespace        = "acme"
  environment      = "prod"
  subscription_id  = "11111111-2222-3333-4444-555555555555"
  location         = "eastus2"
  autoheal_version = "1.0.0"

  existing_network = {
    aks_subnet_id      = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-aks"
    postgres_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pg"
    endpoint_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pe"
    runner_subnet_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-runner"
    temporal_ip        = "10.20.4.11"
    proxy_ip           = "10.20.4.10"
  }
  existing_dns_zone_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"

  aks_node_size     = "Standard_D8s_v5"
  aks_node_count    = 3
  postgres_sku      = "GP_Standard_D4ds_v5"
  runner_node_count = 2

  hostname  = "autoheal.acme.example"
  edge_mode = "loadbalancer"

  deployer_ip_ranges        = ["203.0.113.10"]
  private_endpoints_enabled = true
}

run "brought_network_and_zone" {
  command = plan

  assert {
    condition = (
      output.autoheal_values.global.infra.temporal.internalIP == "10.20.4.11" &&
      output.autoheal_values.global.infra.edge.internalIP == "10.20.4.10"
    )
    error_message = "The reserved addresses are the ones acme's network team gave."
  }

  assert {
    condition = (
      length(module.vnet) == 0 && length(module.aks) == 1 && length(module.postgres) == 1 &&
      length(module.redis) == 1 && length(module.blob) == 1 && length(module.keyvault) == 1
    )
    error_message = "Only the network is brought; everything else is created."
  }

  assert {
    condition     = output.autoheal_values.global.addons.install == true
    error_message = "addons.install is true for a created cluster."
  }

  # The privatelink and Postgres zones are created and linked to vnet-core,
  # because existing_network names none.
  assert {
    condition = (
      length(azurerm_private_dns_zone.postgres) == 1 &&
      azurerm_private_dns_zone_virtual_network_link.postgres[0].virtual_network_id == "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core" &&
      toset(keys(azurerm_private_dns_zone.brought)) == toset(["blob", "vault", "redis"])
    )
    error_message = "A brought network gets the Postgres zone and one privatelink zone per private endpoint, linked to its VNet."
  }

  assert {
    condition     = length(module.dns) == 1 && length(output.required_dns_records) == 0
    error_message = "The records are created in acme.example, pointing at the proxy address."
  }

  assert {
    condition     = length(output.required_role_assignments) == 0
    error_message = "Nothing is listed when we make the grants."
  }

  assert {
    condition     = length(terraform_data.validate_addresses) == 1
    error_message = "The reserved addresses are checked against the AKS subnet."
  }
}

run "zones_given" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id                = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-aks"
      postgres_subnet_id           = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pg"
      endpoint_subnet_id           = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pe"
      runner_subnet_id             = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-runner"
      temporal_ip                  = "10.20.4.11"
      proxy_ip                     = "10.20.4.10"
      postgres_private_dns_zone_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/privateDnsZones/acme-prod.private.postgres.database.azure.com"
      private_dns_zone_ids = {
        blob  = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
        vault = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
        redis = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/privateDnsZones/privatelink.redis.azure.net"
      }
    }
  }

  assert {
    condition     = length(azurerm_private_dns_zone.postgres) == 0 && length(azurerm_private_dns_zone.brought) == 0
    error_message = "Zones acme passes are used, not created."
  }
}

run "grants_listed_for_the_network_team" {
  command = plan

  variables {
    create_role_assignments = false
  }

  assert {
    condition     = contains(output.required_role_assignments, "Network Contributor on vnet-core/snet-aks for acme-prod-autoheal-uami")
    error_message = "The cluster identity's grant on the brought AKS subnet is listed."
  }

  assert {
    condition     = length(output.required_role_assignments) == 6
    error_message = "Three workload grants, the deployer's vault and cluster grants, and the cluster network grant."
  }
}

# --- Input checks --------------------------------------------------------------

run "proxy_ip_outside_the_subnet" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id      = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-aks"
      postgres_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pg"
      endpoint_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pe"
      runner_subnet_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-runner"
      temporal_ip        = "10.20.4.11"
      proxy_ip           = "10.20.8.10"
    }
  }

  expect_failures = [terraform_data.validate_addresses]
}

run "same_address_twice" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id      = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-aks"
      postgres_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pg"
      endpoint_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pe"
      runner_subnet_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-runner"
      temporal_ip        = "10.20.4.11"
      proxy_ip           = "10.20.4.11"
    }
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "created_redis_needs_an_endpoint_subnet" {
  command = plan

  variables {
    private_endpoints_enabled = false
    workload_egress_ip_ranges = ["198.51.100.0/28"]
    existing_network = {
      aks_subnet_id      = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-aks"
      postgres_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-pg"
      runner_subnet_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-core/subnets/snet-runner"
      temporal_ip        = "10.20.4.11"
      proxy_ip           = "10.20.4.10"
    }
  }

  expect_failures = [terraform_data.validate_inputs]
}
