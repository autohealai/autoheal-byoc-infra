# Guards the Blob and Key Vault reachability checks in validation.tf
# (terraform_data.validate_reachability). `terraform validate` does not evaluate
# preconditions; `terraform test` runs a real plan, which does. The providers are
# mocked, so no subscription is touched.
#
# Both checks sit on one resource, so expect_failures can only observe that the
# resource failed, not which check. The suite proves each check by ablation
# against the accepted baseline:
#
#   accepts_apply_and_runtime (deployer + private endpoints)  -> plan succeeds
#   deployer_only_is_rejected (drop private endpoints)        -> rejected
#     => removing the runtime path flips accept to reject, so the runtime check is real
#   private_endpoints_only_is_rejected (drop deployer)        -> rejected
#     => removing the apply path flips accept to reject, so the apply-time check is real

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
  environment          = "play"
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  location             = "centralus"
  hostname             = "autoheal.acme.example"
  autoheal_version     = "1.0.0"
  existing_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"
}

# Accepted baseline: the deployer allow-list opens the apply host, private
# endpoints open the runtime path. Both checks pass, so the plan must succeed.
run "accepts_apply_and_runtime" {
  command = plan

  variables {
    deployer_ip_ranges        = ["203.0.113.10"]
    private_endpoints_enabled = true
  }
}

# A single address written as a /32. The storage firewall rejects /32, so the
# blob module writes the bare address; the provider would fail this plan
# otherwise.
run "accepts_a_slash_32_address" {
  command = plan

  variables {
    deployer_ip_ranges        = ["203.0.113.10/32"]
    private_endpoints_enabled = true
  }
}

# The cluster's outbound CIDRs are an alternative runtime path.
run "accepts_workload_egress_ranges" {
  command = plan

  variables {
    deployer_ip_ranges        = ["203.0.113.10"]
    workload_egress_ip_ranges = ["198.51.100.0/28"]
  }
}

# Allow on both opens both paths at once (a throwaway install).
run "accepts_allow_all" {
  command = plan

  variables {
    storage_network_default_action   = "Allow"
    key_vault_network_default_action = "Allow"
  }
}

# No path at all: both checks reject.
run "deny_all_is_rejected" {
  command = plan

  expect_failures = [terraform_data.validate_reachability]
}

# Drop private endpoints from the baseline: the apply host can still reach the
# account and vault, the pods cannot. Isolates the runtime check.
run "deployer_only_is_rejected" {
  command = plan

  variables {
    deployer_ip_ranges = ["203.0.113.10"]
  }

  expect_failures = [terraform_data.validate_reachability]
}

# Drop the deployer allow-list from the baseline: the pods can reach the account
# and vault, the apply host writing the vault entries cannot. Isolates the
# apply-time check.
run "private_endpoints_only_is_rejected" {
  command = plan

  variables {
    private_endpoints_enabled = true
  }

  expect_failures = [terraform_data.validate_reachability]
}

# A lowercase default action is rejected by variable validation before it can
# reach the Azure API as a confusing deny-all.
run "lowercase_default_action_is_rejected" {
  command = plan

  variables {
    storage_network_default_action = "allow"
  }

  expect_failures = [var.storage_network_default_action]
}
