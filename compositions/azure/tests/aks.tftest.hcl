# Case 1 with the real modules/azure/aks. The other suites override module.aks,
# so this is the one that plans the cluster itself. It guards the cluster output:
# the name and ID must not inherit the sensitive marking of kube_config, or every
# real plan fails with "Output refers to sensitive values".
#
# The mocks are those of create.tftest.hcl, plus the cluster's ID, OIDC issuer
# and kube_config. kubelet_identity is a block, which a mock cannot fill, so the
# module must cope with it empty.

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
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-acme" }
  }
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ContainerService/managedClusters/acme-prod-autoheal"
      oidc_issuer_url = "https://oidc.prod-aks.azure.example/00000000-0000-0000-0000-000000000000/"
      kube_config = [{
        host                   = "https://acme-prod-autoheal.hcp.centralus.azmk8s.io:443"
        cluster_ca_certificate = "Y2EtY2VydA=="
        client_certificate     = ""
        client_key             = ""
        username               = ""
        password               = ""
      }]
    }
  }
}

mock_provider "random" {}

variables {
  namespace            = "acme"
  environment          = "prod"
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  location             = "centralus"
  hostname             = "autoheal.acme.example"
  existing_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"
  deployer_ip_ranges   = ["203.0.113.10"]

  private_endpoints_enabled = true
}

run "cluster_output_is_not_sensitive" {
  command = plan

  assert {
    condition     = output.cluster.name == "acme-prod-autoheal" && output.cluster.resource_group == "rg-acme-prod-autoheal"
    error_message = "The cluster output must carry the created cluster's name and resource group."
  }

  assert {
    condition     = !issensitive(output.cluster.name)
    error_message = "The cluster name must not be sensitive; only kube_config is."
  }

  # The federation of a created cluster's identities is made here, so there is
  # nothing for compositions/azure-cluster.
  assert {
    condition     = output.federation == null
    error_message = "The federation output must be null for a cluster we create."
  }
}
