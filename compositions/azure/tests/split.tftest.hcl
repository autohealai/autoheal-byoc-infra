# Case 2b: acme runs AKS in one subscription (COP, 66666666-...) and gives us
# only the autoheal namespace there. Everything we create goes in another
# subscription (SRE, 11111111-..., subscription_id): a VNet without an AKS
# subnet, Postgres, Redis, storage, both vaults, the identities, the runner and
# the private endpoints. Nothing is created in COP; the cluster and its AKS
# subnet are only read there.
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
    temporal_ip   = "10.40.15.253"
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
      module.vnet[0].subnet_aks_id == "" && module.vnet[0].aks_nsg_id == ""
    )
    error_message = "We create a VNet for the runner, Postgres and endpoints, with no AKS subnet and no NSG."
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

  assert {
    condition     = local.oidc_issuer == "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/aks-cop/"
    error_message = "The workload identities are federated to the COP cluster's issuer."
  }

  assert {
    condition = (
      output.cluster.subscription_id == "66666666-6666-6666-6666-666666666666" &&
      output.cluster.name == "aks-cop" && output.cluster.resource_group == "rg-cop" &&
      output.cluster.endpoint == "https://aks-cop.hcp.eastus2.azmk8s.io:443"
    )
    error_message = "cluster describes the COP cluster, with its subscription."
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
      output.autoheal_values.global.infra.temporal.internalIP == "10.40.15.253" &&
      output.autoheal_values.global.infra.edge.internalIP == "10.40.15.252" &&
      local.tool_response_callback_url == "http://10.40.15.253:8083/api/v1/internal/sandbox-tool-responses" &&
      output.autoheal_values.global.addons.install == false
    )
    error_message = "The reserved addresses are acme's, in the COP AKS subnet."
  }

  assert {
    condition     = length(module.dns) == 1 && length(output.required_dns_records) == 0
    error_message = "The records are created in the SRE zone, pointing at the COP proxy address."
  }

  # By position: the network path line (6) holds the ID of the VNet we create,
  # which a plan does not know yet.
  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 9 &&
      output.required_cluster_owner_actions[3] == "A Kubernetes role for the deployer (object ID 12121212-1212-1212-1212-121212121212) in the namespace autoheal: Azure Kubernetes Service RBAC Admin at /subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop/providers/Microsoft.ContainerService/managedClusters/aks-cop/namespaces/autoheal with Azure RBAC, or a RoleBinding to the admin ClusterRole with Kubernetes RBAC" &&
      output.required_cluster_owner_actions[5] == "An NSG rule on the AKS subnet vnet-cop/snet-aks: allow the runner subnet (10.70.19.0/24) to 10.40.15.253 on TCP 7233 and 8083, and deny every other source to that address on those ports" &&
      output.required_cluster_owner_actions[7] == "A path for users to 10.40.15.252 on TCP 443, the address of the Autoheal proxy" &&
      output.required_cluster_owner_actions[8] == "Private DNS resolution in vnet-cop for acme-prod.private.postgres.database.azure.com, privatelink.blob.core.windows.net, privatelink.redis.azure.net, privatelink.vaultcore.azure.net: link the zones to that VNet, or forward them from your DNS servers"
    )
    error_message = "required_cluster_owner_actions has nine lines: two deployer roles, the namespace, its role, the cluster features, the NSG rule, the network path, the user path and DNS."
  }
}

# The VNet we create, with known IDs, to check that the runner, Postgres, the
# endpoints and the zone links all land in SRE.
run "workload_vnet_in_our_subscription" {
  command = plan

  override_module {
    target = module.vnet
    outputs = {
      vnet_id                   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal"
      vnet_name                 = "acme-prod-autoheal"
      subnet_aks_id             = ""
      subnet_db_id              = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal/subnets/snet-db"
      subnet_pe_id              = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal/subnets/snet-pe"
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
    condition = alltrue([
      for id in [local.runner_subnet_id, local.postgres_subnet_id, local.endpoint_subnet_id, local.workload_vnet_id] :
      startswith(id, "/subscriptions/11111111-1111-1111-1111-111111111111/")
    ])
    error_message = "The runner, Postgres and endpoint subnets are in SRE."
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
    condition     = output.required_cluster_owner_actions[6] == "A network path between /subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop and /subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal: VNet peering in both directions, or both VNets through your hub. Pods reach Postgres, Redis, storage and the vaults over it, and the runner VMs reach 10.40.15.253"
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

  # Nine lines, the last the join permission, so there is no DNS line.
  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 9 &&
      output.required_cluster_owner_actions[8] == "Network Contributor, or a role with Microsoft.Network/virtualNetworks/join/action, on /subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop for the deployer (object ID 12121212-1212-1212-1212-121212121212): the apply links acme-prod.private.postgres.database.azure.com, privatelink.blob.core.windows.net, privatelink.redis.azure.net, privatelink.vaultcore.azure.net to that VNet"
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
      temporal_ip                  = "10.40.15.253"
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

  # Nine lines: no join permission, since we link nothing, and the DNS line last.
  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 9 &&
      output.required_cluster_owner_actions[8] == "Private DNS resolution in vnet-cop for acme.private.postgres.database.azure.com, privatelink.blob.core.windows.net, privatelink.redis.azure.net, privatelink.vaultcore.azure.net: link the zones to that VNet, or forward them from your DNS servers"
    )
    error_message = "The owner resolves acme's zones from the COP VNet."
  }
}

# acme's SRE network team gives the subnets. We create no VNet and link our
# zones to the runner subnet's VNet.
run "subnets_given_in_our_subscription" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id      = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      runner_subnet_id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-runner"
      postgres_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pg"
      endpoint_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pe"
      temporal_ip        = "10.40.15.253"
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
    condition     = output.required_cluster_owner_actions[5] == "An NSG rule on the AKS subnet vnet-cop/snet-aks: allow the runner subnet vnet-sre/snet-runner to 10.40.15.253 on TCP 7233 and 8083, and deny every other source to that address on those ports"
    error_message = "The NSG rule names the given runner subnet."
  }
}

# --- Mixes that cannot work ------------------------------------------------------

# A private endpoint must be in the subscription of its VNet.
run "endpoint_subnet_in_the_cluster_subscription" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id      = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      runner_subnet_id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-runner"
      postgres_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pg"
      endpoint_subnet_id = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-pe"
      temporal_ip        = "10.40.15.253"
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
      temporal_ip   = "10.40.15.253"
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

# Some SRE subnets are given, so we create no VNet, and the runner needs one.
run "runner_subnet_missing" {
  command = plan

  variables {
    existing_network = {
      aks_subnet_id      = "/subscriptions/66666666-6666-6666-6666-666666666666/resourceGroups/rg-cop-net/providers/Microsoft.Network/virtualNetworks/vnet-cop/subnets/snet-aks"
      postgres_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pg"
      endpoint_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sre-net/providers/Microsoft.Network/virtualNetworks/vnet-sre/subnets/snet-pe"
      temporal_ip        = "10.40.15.253"
      proxy_ip           = "10.40.15.252"
    }
  }

  expect_failures = [terraform_data.validate_inputs]
}
