# Case 2b: acme runs AKS in one subscription (COP, 66666666-...) and gives us
# only the autoheal namespace there. Everything we create goes in another
# subscription (SRE, 11111111-..., subscription_id): a VNet without an AKS
# subnet, Postgres, Redis, storage, both vaults, the identities and the private
# endpoints. Nothing is created or read in COP: compositions/azure-cluster reads
# the cluster after this apply and federates the identities to it.
#
# The composition has no peering resource, so none can be planned: acme connects
# the two VNets (required_cluster_owner_actions).

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
  network_cidr = "10.70.0.0/16"

  existing_dns_zone_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/acme.example"
  hostname             = "autoheal.acme.example"
  edge_mode            = "loadbalancer"

  private_endpoints_enabled = true
  deployer_ip_ranges        = ["203.0.113.10/32"]

  llm_api_key = "llm-key"
}

# Values a real plan knows. Terraform keeps the IDs of created resources unknown
# at plan, so the next run checks where they go.
run "cluster_in_another_subscription" {
  command = plan

  assert {
    condition     = length(module.aks) == 0 && local.cluster_in_other_subscription && local.cluster_subscription_id == "66666666-6666-6666-6666-666666666666"
    error_message = "The cluster is brought from COP; no cluster is created."
  }

  assert {
    condition = (
      length(module.vnet) == 1 && local.create_workload_network && !local.create_network &&
      module.vnet[0].subnet_aks_id == ""
    )
    error_message = "We create a VNet for Postgres and the endpoints, with no AKS subnet."
  }

  assert {
    condition = (
      length(module.pe_blob) == 1 && length(module.pe_vault) == 1 && length(module.pe_runtime_vault) == 1 && length(module.pe_redis) == 1 &&
      length(module.postgres) == 1
    )
    error_message = "The private endpoints and Postgres are created."
  }

  assert {
    condition = (
      length(azurerm_private_dns_zone.brought) == 3 && length(azurerm_private_dns_zone.postgres) == 1 &&
      length(azurerm_private_dns_zone_virtual_network_link.brought) == 3 && length(azurerm_private_dns_zone_virtual_network_link.postgres) == 1
    )
    error_message = "We create the Postgres and privatelink zones and link each once."
  }

  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.cluster_vnet) == 0 && length(azurerm_private_dns_zone_virtual_network_link.postgres_cluster_vnet) == 0
    error_message = "Without cluster_vnet_dns_link_enabled no zone is linked to the COP VNet."
  }

  # The COP cluster is not read, so no identity is federated here. federation
  # hands the identities, which are in SRE, to compositions/azure-cluster.
  assert {
    condition = (
      local.oidc_issuer == "" &&
      output.federation != null &&
      output.federation.subscription_id == "11111111-1111-1111-1111-111111111111" &&
      sort(keys(output.federation.identities)) == tolist(["agents_worker", "api_server", "secrets"])
    )
    error_message = "federation names the three identities in SRE, for compositions/azure-cluster to federate to the COP cluster."
  }

  assert {
    condition = (
      output.cluster.subscription_id == "66666666-6666-6666-6666-666666666666" &&
      output.cluster.name == "aks-cop" && output.cluster.resource_group == "rg-cop" &&
      output.cluster.endpoint == "" && output.cluster.ca_certificate == ""
    )
    error_message = "cluster names the COP cluster, with its subscription, and leaves the endpoint and CA certificate to compositions/azure-cluster."
  }

  assert {
    condition = (
      output.network.vnet_name == module.vnet[0].vnet_name &&
      output.network.resource_group_name == "rg-acme-prod-autoheal" &&
      tolist(output.network.address_space) == tolist(["10.70.0.0/16"]) &&
      output.network.cluster_vnet_id == "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop" &&
      endswith(output.network.aks_subnet_id, "/vnet-cop/subnets/snet-aks")
    )
    error_message = "network shows the VNet we create and the COP VNet apart."
  }

  assert {
    condition = (
      !contains(keys(output.autoheal_values.global.infra), "temporal") &&
      output.autoheal_values.global.infra.edge.internalIP == "10.40.15.252" &&
      output.autoheal_values.global.addons.install == false
    )
    error_message = "The proxy address is acme's, in the COP AKS subnet, and there is no Temporal address."
  }

  assert {
    condition     = length(module.dns) == 1 && length(output.required_dns_records) == 0
    error_message = "The records are created in the SRE zone, pointing at the COP proxy address."
  }

  # By position: the network path line (4) holds the ID of the VNet we create,
  # which a plan does not know yet.
  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 7 &&
      output.required_cluster_owner_actions[0] == "Azure Kubernetes Service Cluster User Role on aks-cop for the deployer (object ID 12121212-1212-1212-1212-121212121212): compositions/azure-cluster reads the cluster's OIDC issuer, endpoint and CA certificate" &&
      output.required_cluster_owner_actions[2] == "A Kubernetes role for the deployer (object ID 12121212-1212-1212-1212-121212121212) in the namespace autoheal: Azure Kubernetes Service RBAC Admin at /subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop/providers/Microsoft.ContainerService/managedClusters/aks-cop/namespaces/autoheal with Azure RBAC, or a RoleBinding to the admin ClusterRole with Kubernetes RBAC" &&
      output.required_cluster_owner_actions[5] == "A path for users to 10.40.15.252 on TCP 443, the address of the Autoheal proxy" &&
      output.required_cluster_owner_actions[6] == "Private DNS resolution in vnet-cop for acme-prod.private.postgres.database.azure.com, privatelink.blob.core.windows.net, privatelink.redis.azure.net, privatelink.vaultcore.azure.net: link the zones to that VNet, or forward them from your DNS servers"
    )
    error_message = "required_cluster_owner_actions has seven lines: the deployer's cluster role, the namespace, its role, the cluster features, the network path, the user path and DNS."
  }
}

# The VNet we create, with known IDs, to check that Postgres, the endpoints and
# the zone links all land in SRE.
run "workload_vnet_in_our_subscription" {
  command = plan

  override_module {
    target = module.vnet
    outputs = {
      vnet_id                      = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal"
      vnet_name                    = "acme-prod-autoheal"
      subnet_aks_id                = ""
      subnet_db_id                 = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal/subnets/snet-db"
      subnet_pe_id                 = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal/subnets/snet-pe"
      pg_private_dns_zone_id       = ""
      blob_private_dns_zone_id     = ""
      vault_private_dns_zone_id    = ""
      redis_private_dns_zone_id    = ""
      foundry_private_dns_zone_ids = []
    }
  }

  assert {
    condition = alltrue([
      for id in [local.postgres_subnet_id, local.endpoint_subnet_id, local.workload_vnet_id] :
      startswith(id, "/subscriptions/11111111-1111-1111-1111-111111111111/")
    ])
    error_message = "The Postgres and endpoint subnets are in SRE."
  }

  assert {
    condition = (
      alltrue([for l in azurerm_private_dns_zone_virtual_network_link.brought : l.virtual_network_id == "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal"]) &&
      azurerm_private_dns_zone_virtual_network_link.postgres[0].virtual_network_id == "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal"
    )
    error_message = "The zones we create are linked to the SRE VNet."
  }

  assert {
    condition     = output.network.vnet_id == "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal"
    error_message = "network.vnet_id is the SRE VNet."
  }

  assert {
    condition     = output.required_cluster_owner_actions[4] == "A network path between /subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop and /subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal: VNet peering in both directions, or both VNets through your hub. Pods reach Postgres, Redis, storage and the vaults over it"
    error_message = "The owner connects the COP VNet and the SRE VNet."
  }
}

# The deployer may join the COP VNet, so the zones we create are linked to it
# too. The owner then has no DNS line, but must allow the join.
run "zones_linked_to_the_cluster_vnet" {
  command = plan

  variables {
    cluster_vnet_dns_link_enabled = true
  }

  assert {
    condition = (
      length(azurerm_private_dns_zone_virtual_network_link.cluster_vnet) == 3 &&
      length(azurerm_private_dns_zone_virtual_network_link.postgres_cluster_vnet) == 1 &&
      alltrue([for l in azurerm_private_dns_zone_virtual_network_link.cluster_vnet : l.virtual_network_id == "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop"]) &&
      azurerm_private_dns_zone_virtual_network_link.postgres_cluster_vnet[0].virtual_network_id == "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop"
    )
    error_message = "Every zone we create is also linked to the COP VNet."
  }

  assert {
    condition = (
      length(azurerm_private_dns_zone_virtual_network_link.brought) == 3 &&
      length(azurerm_private_dns_zone_virtual_network_link.postgres) == 1
    )
    error_message = "The SRE VNet keeps its links."
  }

  # Seven lines, the last the join permission, so there is no DNS line.
  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 7 &&
      output.required_cluster_owner_actions[6] == "Network Contributor, or a role with Microsoft.Network/virtualNetworks/join/action, on /subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop for the deployer (object ID 12121212-1212-1212-1212-121212121212): the apply links acme-prod.private.postgres.database.azure.com, privatelink.blob.core.windows.net, privatelink.redis.azure.net, privatelink.vaultcore.azure.net to that VNet"
    )
    error_message = "The owner allows the join and resolves no zone."
  }
}

# acme's central DNS holds the zones. We create none, link none, and the owner
# makes sure the COP VNet resolves them.
run "customer_zones" {
  command = plan

  variables {
    cluster_vnet_dns_link_enabled = true
    existing_network = {
      aks_subnet_id                = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      proxy_ip                     = "10.40.15.252"
      postgres_private_dns_zone_id = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/acme.private.postgres.database.azure.com"
      private_dns_zone_ids = {
        blob  = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
        vault = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
        redis = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.redis.azure.net"
      }
    }
  }

  assert {
    condition = (
      length(azurerm_private_dns_zone.brought) == 0 && length(azurerm_private_dns_zone.postgres) == 0 &&
      length(azurerm_private_dns_zone_virtual_network_link.cluster_vnet) == 0 &&
      length(azurerm_private_dns_zone_virtual_network_link.postgres_cluster_vnet) == 0
    )
    error_message = "acme's zones are used as they are; we create and link none."
  }

  # Seven lines: no join permission, since we link nothing, and the DNS line last.
  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 7 &&
      output.required_cluster_owner_actions[6] == "Private DNS resolution in vnet-cop for acme.private.postgres.database.azure.com, privatelink.blob.core.windows.net, privatelink.redis.azure.net, privatelink.vaultcore.azure.net: link the zones to that VNet, or forward them from your DNS servers"
    )
    error_message = "The owner resolves acme's zones from the COP VNet."
  }
}

# acme's SRE network team gives the subnets. We create no VNet and link our
# zones to the VNet of those subnets.
run "subnets_given_in_our_subscription" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id      = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      postgres_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pg"
      endpoint_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pe"
      proxy_ip           = "10.40.15.252"
    }
  }

  assert {
    condition = (
      length(module.vnet) == 0 &&
      local.workload_vnet_id == "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre" &&
      alltrue([for l in azurerm_private_dns_zone_virtual_network_link.brought : l.virtual_network_id == local.workload_vnet_id])
    )
    error_message = "No VNet is created; the zones are linked to the SRE VNet of the given subnets."
  }

  assert {
    condition     = output.network.vnet_name == "vnet-sre" && output.network.resource_group_name == "rg-sre-net" && length(output.network.address_space) == 0
    error_message = "network describes the given SRE VNet."
  }

  assert {
    condition     = output.required_cluster_owner_actions[4] == "A network path between /subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop and /subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre: VNet peering in both directions, or both VNets through your hub. Pods reach Postgres, Redis, storage and the vaults over it"
    error_message = "The owner connects the COP VNet and the given SRE VNet."
  }
}

# An existing_network written for an earlier release still has temporal_ip and
# runner_subnet_id. The plan accepts them and reads neither: we still create the
# SRE VNet, and no Temporal address reaches the chart. (How the test shows
# var.existing_network differs: Terraform drops the two attributes there,
# OpenTofu keeps them, so this run does not assert on it.)
run "old_network_attributes_are_ignored" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id    = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      runner_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-runner"
      temporal_ip      = "10.40.15.253"
      proxy_ip         = "10.40.15.252"
    }
  }

  assert {
    condition     = length(module.vnet) == 1 && local.create_workload_network
    error_message = "runner_subnet_id is not a workload subnet: we still create the SRE VNet."
  }

  assert {
    condition = (
      !contains(keys(output.autoheal_values.global.infra), "temporal") &&
      output.autoheal_values.global.infra.edge.internalIP == "10.40.15.252" &&
      length(output.required_cluster_owner_actions) == 7
    )
    error_message = "temporal_ip reaches neither the chart values nor the owner actions."
  }
}

# --- Mixes that cannot work ------------------------------------------------------

# A private endpoint must be in the subscription of its VNet.
run "endpoint_subnet_in_the_cluster_subscription" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id      = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      postgres_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pg"
      endpoint_subnet_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-pe"
      proxy_ip           = "10.40.15.252"
    }
  }

  expect_failures = [terraform_data.validate_subscriptions]
}

run "aks_subnet_in_a_third_subscription" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-other/subnets/snet-aks"
      proxy_ip      = "10.40.15.252"
    }
  }

  expect_failures = [terraform_data.validate_subscriptions]
}

run "postgres_in_the_cluster_subscription" {
  command = plan

  variables {
    existing_postgres_id    = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-cop"
    postgres_admin_password = "cop-admin-password"
  }

  expect_failures = [terraform_data.validate_subscriptions]
}

run "dns_zone_in_the_cluster_subscription" {
  command = plan

  variables {
    existing_dns_zone_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-dns/providers/Microsoft.Network/dnszones/acme.example"
  }

  expect_failures = [terraform_data.validate_subscriptions]
}

# The same zone works when acme creates the records.
run "dns_zone_in_the_cluster_subscription_without_records" {
  command = plan

  variables {
    existing_dns_zone_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-dns/providers/Microsoft.Network/dnszones/acme.example"
    create_dns_records   = false
  }

  assert {
    condition     = length(module.dns) == 0 && length(output.required_dns_records) == 3
    error_message = "With create_dns_records = false the records are listed for acme."
  }
}
