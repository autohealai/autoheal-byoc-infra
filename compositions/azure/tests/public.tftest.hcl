# Case 2c: like case 2b (split.tftest.hcl), acme runs AKS in COP (66666666-...)
# and everything we create goes in SRE (11111111-...), but the two VNets are not
# connected (cluster_network_path = public). Postgres and the vaults let in
# acme's outbound addresses only, storage lets in those addresses and a network
# rule for acme's AKS subnet that the cluster owner adds after the apply, and
# Redis is public. We create no VNet.

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
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-acme" }
  }
}

mock_provider "random" {}

variables {
  namespace       = "acme"
  environment     = "prod"
  subscription_id = "11111111-1111-1111-1111-111111111111"
  location        = "eastus2"

  existing_aks_cluster_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop/providers/Microsoft.ContainerService/managedClusters/aks-cop"
  existing_network = {
    aks_subnet_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
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

run "public_path" {
  command = plan

  assert {
    condition     = length(module.vnet) == 0
    error_message = "No VNet is created on the public path."
  }

  assert {
    condition = (
      output.network.vnet_id == "" && output.network.vnet_name == "" && output.network.resource_group_name == "" &&
      length(output.network.address_space) == 0 && output.network.private_endpoint_subnet_id == "" &&
      output.network.cluster_vnet_id == "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop" &&
      output.network.aks_subnet_id == "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
    )
    error_message = "network has no workload VNet and names acme's AKS subnet and its VNet."
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
    condition     = length(module.redis) == 1 && local.public_path
    error_message = "We create Redis, with a public endpoint."
  }

  # Contract 3.0.0: no Temporal address and no Temporal load balancers.
  assert {
    condition = (
      !contains(keys(output.autoheal_values), "temporalFrontendLoadBalancer") &&
      !contains(keys(output.autoheal_values), "toolResponseLoadBalancer") &&
      !contains(keys(output.autoheal_values.global.infra), "temporal") &&
      output.autoheal_values.global.infra.edge.internalIP == "10.40.15.252"
    )
    error_message = "autoheal_values has no Temporal address or load balancer keys; the proxy keeps its internal address."
  }

  assert {
    condition     = output.autoheal_values.global.edge.exposure == "internal"
    error_message = "The proxy stays internal unless edge_exposure is public."
  }

  # The identities are in SRE, not in the cluster's subscription.
  assert {
    condition = (
      output.federation != null &&
      output.federation.subscription_id == "11111111-1111-1111-1111-111111111111" &&
      output.cluster.subscription_id == "66666666-6666-6666-6666-666666666666" &&
      output.cluster.endpoint == ""
    )
    error_message = "federation names subscription_id, where the identities are; cluster names COP with no endpoint."
  }

  # By position: four cluster lines, then the storage network rule, the
  # outbound addresses and the user path. No network path or DNS line.
  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 7 &&
      output.required_cluster_owner_actions[4] == "The Microsoft.Storage service endpoint on the AKS subnet vnet-cop/snet-aks, and after this apply a network rule for that subnet on the storage account acmeprodautoheal: az storage account network-rule add --resource-group rg-acme-prod-autoheal --account-name acmeprodautoheal --subnet /subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks. Pods in the account's region reach it from that subnet, where its IP rules do not apply. Whoever runs it needs Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action on the subnet and write on the account; Terraform leaves the rule alone" &&
      output.required_cluster_owner_actions[5] == "Fixed public outbound addresses for aks-cop: 198.51.100.20/32, 198.51.100.32/28. Postgres and the Key Vaults let in only them" &&
      output.required_cluster_owner_actions[6] == "A path for users to 10.40.15.252 on TCP 443, the address of the Autoheal proxy"
    )
    error_message = "Seven lines: the four cluster lines, the storage network rule, the outbound addresses and the user path."
  }
}

# A storage account open to all networks needs no rule for the AKS subnet.
run "public_path_open_storage" {
  command = plan

  variables {
    storage_network_default_action = "Allow"
  }

  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 6 &&
      !anytrue([for l in output.required_cluster_owner_actions : startswith(l, "The Microsoft.Storage service endpoint")])
    )
    error_message = "With storage_network_default_action = Allow there is no storage network rule line."
  }
}

# --- A public proxy -------------------------------------------------------------

# Users and webhooks reach the proxy on its own static public IP, also in the
# node resource group.
run "public_proxy" {
  command = plan

  variables {
    edge_exposure = "public"
    existing_network = {
      aks_subnet_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      proxy_ip      = "20.30.40.60"
    }
  }

  assert {
    condition = (
      output.autoheal_values.global.edge.exposure == "public" &&
      output.autoheal_values.global.infra.edge.internalIP == "20.30.40.60"
    )
    error_message = "The chart puts the proxy's public load balancer on the proxy IP."
  }

  assert {
    condition     = local.dns_target == "20.30.40.60" && length(module.dns) == 1
    error_message = "The DNS records point to the proxy's public IP."
  }

  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 8 &&
      startswith(output.required_cluster_owner_actions[4], "The Microsoft.Storage service endpoint on the AKS subnet vnet-cop/snet-aks") &&
      output.required_cluster_owner_actions[6] == "A Standard static public IP 20.30.40.60 in the node resource group of aks-cop: the Autoheal proxy's load balancer uses it" &&
      output.required_cluster_owner_actions[7] == "An NSG rule on the AKS subnet vnet-cop/snet-aks: allow your users and webhook senders, or the internet, to 20.30.40.60 on TCP 443 and 80, the public address of the Autoheal proxy"
    )
    error_message = "Eight lines: the public path lines, then the proxy's static IP and its NSG rule in place of the private user path."
  }
}

# --- Mixes that cannot work ------------------------------------------------------

run "public_proxy_needs_a_public_address" {
  command = plan

  variables {
    edge_exposure = "public"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "public_proxy_needs_loadbalancer_mode" {
  command = plan

  variables {
    edge_exposure = "public"
    edge_mode     = "istio"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "public_proxy_needs_a_public_dns_zone" {
  command = plan

  variables {
    edge_exposure        = "public"
    existing_dns_zone_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/acme.example"
    existing_network = {
      aks_subnet_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      proxy_ip      = "20.30.40.60"
    }
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "public_path_needs_another_subscription" {
  command = plan

  variables {
    existing_aks_cluster_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre/providers/Microsoft.ContainerService/managedClusters/aks-sre"
    existing_network = {
      aks_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-aks"
      proxy_ip      = "10.40.15.252"
    }
  }

  expect_failures = [terraform_data.validate_public_path]
}

run "public_path_needs_the_cluster_addresses" {
  command = plan

  variables {
    workload_egress_ip_ranges = []
  }

  expect_failures = [terraform_data.validate_public_path, terraform_data.validate_reachability]
}

# Pods reach the services over public endpoints, so brought Postgres and
# endpoint subnets have no use.
run "public_path_takes_no_workload_subnets" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id      = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      postgres_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pg"
      endpoint_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pe"
      proxy_ip           = "10.40.15.252"
    }
  }

  expect_failures = [terraform_data.validate_public_path]
}
