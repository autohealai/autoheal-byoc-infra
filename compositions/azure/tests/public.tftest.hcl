# Case 2c: like case 2b (split.tftest.hcl), acme runs AKS in COP (66666666-...)
# and everything we create goes in SRE (11111111-...), but the two VNets are not
# connected (cluster_network_path = public). Postgres and the vaults let in
# acme's outbound addresses only, storage lets in acme's AKS subnet, Redis is
# public, and Temporal is published on a static public IP in COP that only the
# runner's NAT address may reach. Our VNet has only the runner subnet.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "12121212-1212-1212-1212-121212121212"
      subscription_id = "11111111-1111-1111-1111-111111111111"
    }
  }

  # OpenTofu fills computed attributes with random strings at plan time, and the
  # provider rejects them where it parses an Azure ID. These defaults give each
  # created resource a well-formed ID in SRE. Terraform keeps them unknown until
  # apply.
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal" }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal" }
  }
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal/subnets/snet-acme" }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/privateDnsZones/privatelink.acme.example" }
  }
  mock_resource "azurerm_storage_account" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Storage/storageAccounts/stacme" }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme"
      vault_uri = "https://kv-acme.vault.azure.net/"
    }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acme"
      principal_id = "44444444-4444-4444-4444-444444444444"
      client_id    = "55555555-5555-5555-5555-555555555555"
      tenant_id    = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "azurerm_managed_redis" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Cache/redisEnterprise/redis-acme" }
  }
  mock_resource "azurerm_nat_gateway" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/natGateways/ng-acme" }
  }
  mock_resource "azurerm_public_ip" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/publicIPAddresses/pip-acme" }
  }
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-acme" }
  }
}

# COP, as the azurerm.cluster provider reads it: acme's cluster and its AKS
# subnet.
mock_provider "azurerm" {
  alias = "cluster"

  mock_data "azurerm_subnet" {
    defaults = { address_prefixes = ["10.40.0.0/20"] }
  }
  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      oidc_issuer_enabled        = true
      oidc_issuer_url            = "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/aks-cop/"
      node_resource_group        = "MC_rg-cop_aks-cop_eastus2"
      key_vault_secrets_provider = [{ secret_rotation_enabled = false, secret_rotation_interval = "2m", secret_identity = [] }]
      kubelet_identity = [{
        client_id                 = "77777777-0000-0000-0000-000000000001"
        object_id                 = "77777777-0000-0000-0000-000000000002"
        user_assigned_identity_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/MC_rg-cop/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aks-cop-agentpool"
      }]
      kube_config = [{
        host                   = "https://aks-cop.hcp.eastus2.azmk8s.io:443"
        cluster_ca_certificate = "Y2EtY2VydA=="
        client_certificate     = ""
        client_key             = ""
        password               = ""
        username               = ""
      }]
    }
  }
}

mock_provider "random" {}

mock_provider "tls" {
  mock_resource "tls_private_key" {
    defaults = { public_key_openssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPdIPEGmxag1iAM9TJa938oKt9VfcpW75Ta8FpAEpXUT acme-test" }
  }
}

variables {
  namespace        = "acme"
  environment      = "prod"
  subscription_id  = "11111111-1111-1111-1111-111111111111"
  location         = "eastus2"
  autoheal_version = "1.0.0"

  existing_aks_cluster_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop/providers/Microsoft.ContainerService/managedClusters/aks-cop"
  existing_network = {
    aks_subnet_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
    temporal_ip   = "20.30.40.50"
    proxy_ip      = "10.40.15.252"
  }
  network_cidr         = "10.70.0.0/16"
  cluster_network_path = "public"

  existing_dns_zone_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"
  hostname             = "autoheal.acme.example"
  edge_mode            = "loadbalancer"

  deployer_ip_ranges        = ["203.0.113.10/32"]
  workload_egress_ip_ranges = ["198.51.100.20/32", "198.51.100.32/28"]

  llm_api_key = "llm-key"
}

# Values a real plan knows. The runner's NAT address is known only after apply,
# so the next run checks the lines that hold it.
run "public_path" {
  command = plan

  assert {
    condition = (
      length(module.vnet) == 1 && module.vnet[0].subnet_aks_id == "" &&
      module.vnet[0].subnet_db_id == "" && module.vnet[0].subnet_pe_id == ""
    )
    error_message = "Our VNet has only the runner subnet."
  }

  assert {
    condition = (
      length(module.pe_blob) + length(module.pe_vault) + length(module.pe_runtime_vault) + length(module.pe_redis) == 0 &&
      length(azurerm_private_dns_zone.brought) + length(azurerm_private_dns_zone.postgres) == 0 &&
      length(azurerm_private_dns_zone_virtual_network_link.brought) + length(azurerm_private_dns_zone_virtual_network_link.postgres) == 0 &&
      length(azurerm_private_dns_zone_virtual_network_link.cluster_vnet) + length(azurerm_private_dns_zone_virtual_network_link.postgres_cluster_vnet) == 0
    )
    error_message = "No private endpoint, private DNS zone or zone link."
  }

  assert {
    condition = jsonencode(module.postgres[0].firewall_rules) == jsonencode({
      "allow-198-51-100-20-32" = { start = "198.51.100.20", end = "198.51.100.20" }
      "allow-198-51-100-32-28" = { start = "198.51.100.32", end = "198.51.100.47" }
    })
    error_message = "Postgres lets in acme's outbound addresses only."
  }

  assert {
    condition     = tolist(local.storage_allowed_subnet_ids) == tolist(["/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"])
    error_message = "Storage lets in acme's AKS subnet, since IP rules do not apply in the same region."
  }

  assert {
    condition     = length(module.redis) == 1 && local.public_path
    error_message = "We create Redis, with a public endpoint."
  }

  assert {
    condition = (
      output.autoheal_values.temporalFrontendLoadBalancer == { enabled = false } &&
      output.autoheal_values.toolResponseLoadBalancer == { enabled = false } &&
      output.autoheal_values.global.infra.temporal.internalIP == "20.30.40.50" &&
      output.autoheal_values.global.infra.edge.internalIP == "10.40.15.252" &&
      local.tool_response_callback_url == "http://20.30.40.50:8083/api/v1/internal/sandbox-tool-responses"
    )
    error_message = "The chart's internal Temporal load balancers are off; the runner reaches the public address."
  }

  assert {
    condition     = output.temporal_public_endpoint.ip == "20.30.40.50"
    error_message = "temporal_public_endpoint names the static public IP for compositions/app."
  }

  # By position: the NSG line (5) holds the runner's NAT address.
  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 10 &&
      output.required_cluster_owner_actions[6] == "A Standard static public IP 20.30.40.50 in MC_rg-cop_aks-cop_eastus2, the node resource group of aks-cop: the public Temporal and tool-response load balancers use it" &&
      output.required_cluster_owner_actions[7] == "The Microsoft.Storage service endpoint on the AKS subnet vnet-cop/snet-aks, and Network Contributor or a role with Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action on it for the deployer (object ID 12121212-1212-1212-1212-121212121212): the storage account lets that subnet in" &&
      output.required_cluster_owner_actions[8] == "Fixed public outbound addresses for aks-cop: 198.51.100.20/32, 198.51.100.32/28. Postgres and the Key Vaults let in only them" &&
      output.required_cluster_owner_actions[9] == "A path for users to 10.40.15.252 on TCP 443, the address of the Autoheal proxy"
    )
    error_message = "Ten lines: the five cluster lines, the NSG rule, the static IP, the service endpoint, the outbound addresses and the user path. No network path or DNS line."
  }
}

# The runner's NAT address, with the VNet's outputs known.
run "runner_address" {
  command = plan

  override_module {
    target = module.vnet
    outputs = {
      vnet_id                   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal"
      vnet_name                 = "acme-prod-autoheal"
      subnet_aks_id             = ""
      subnet_db_id              = ""
      subnet_pe_id              = ""
      subnet_runner_id          = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal/subnets/snet-runner"
      aks_nsg_id                = ""
      aks_nsg_name              = ""
      runner_nat_public_ip      = "198.51.100.7"
      pg_private_dns_zone_id    = ""
      blob_private_dns_zone_id  = ""
      vault_private_dns_zone_id = ""
      redis_private_dns_zone_id = ""
    }
  }

  assert {
    condition     = tolist(output.temporal_public_endpoint.allowed_source_ranges) == tolist(["198.51.100.7/32"])
    error_message = "Only the runner's NAT address may reach the public Temporal address."
  }

  assert {
    condition     = output.required_cluster_owner_actions[5] == "An NSG rule on the AKS subnet vnet-cop/snet-aks: allow the runner VMs' outbound address 198.51.100.7 to 20.30.40.50 on TCP 7233 and 8083, and deny every other source to that address on those ports"
    error_message = "The NSG rule lets the runner's NAT address reach the public Temporal address."
  }
}

# --- Mixes that cannot work ------------------------------------------------------

run "public_path_needs_another_subscription" {
  command = plan

  variables {
    existing_aks_cluster_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre/providers/Microsoft.ContainerService/managedClusters/aks-sre"
    existing_network = {
      aks_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-aks"
      temporal_ip   = "20.30.40.50"
      proxy_ip      = "10.40.15.252"
    }
  }

  expect_failures = [terraform_data.validate_public_path, terraform_data.validate_inputs]
}

run "public_path_needs_the_cluster_addresses" {
  command = plan

  variables {
    workload_egress_ip_ranges = []
  }

  expect_failures = [terraform_data.validate_public_path, terraform_data.validate_reachability]
}

run "public_path_creates_the_runner_network" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id    = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      runner_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-runner"
      temporal_ip      = "20.30.40.50"
      proxy_ip         = "10.40.15.252"
    }
  }

  expect_failures = [terraform_data.validate_public_path]
}

run "public_path_needs_a_public_temporal_ip" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      temporal_ip   = "10.40.15.253"
      proxy_ip      = "10.40.15.252"
    }
  }

  expect_failures = [terraform_data.validate_public_path]
}
