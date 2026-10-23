# Plan-time checks with plain messages. Each group is a terraform_data resource
# whose preconditions fail the plan, so an impossible mix of inputs or an
# unsuitable brought resource stops before anything is created. Groups that read
# a brought resource exist only when that resource is brought.
#
# (Input validation blocks cannot refer to other variables on Terraform 1.7, so
# checks that combine inputs live here.)

# --- Combinations of inputs --------------------------------------------------

resource "terraform_data" "validate_inputs" {
  lifecycle {
    precondition {
      condition     = local.create_cluster || !local.create_network
      error_message = "existing_aks_cluster_id is set but existing_network is not. A brought cluster already sits in a network: set existing_network to its AKS subnet, a runner subnet and the reserved temporal_ip."
    }
    precondition {
      condition     = local.create_vnet || try(var.existing_network.runner_subnet_id, "") != ""
      error_message = "existing_network.runner_subnet_id is required: a subnet for the runner VMs. Only for a cluster in another subscription, with the runner, Postgres and endpoint subnets all empty, do we create a VNet for them."
    }
    precondition {
      condition     = local.create_vnet || local.public_path || !local.create_postgres || try(var.existing_network.postgres_subnet_id, "") != ""
      error_message = "We create the Postgres server (no existing_postgres_id) in a brought network, so existing_network.postgres_subnet_id is required: a subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
    }
    precondition {
      condition     = local.create_network || var.edge_mode != "loadbalancer" || try(var.existing_network.proxy_ip, "") != ""
      error_message = "edge_mode is loadbalancer in a brought network, so existing_network.proxy_ip is required: a free address in the AKS subnet for the proxy's internal load balancer."
    }
    precondition {
      condition     = local.proxy_ip == "" || local.proxy_ip != local.temporal_ip || local.proxy_shares_temporal_ip
      error_message = "existing_network.temporal_ip and existing_network.proxy_ip must be different addresses. Only a public proxy (edge_exposure = public) on cluster_network_path = public may share the public Temporal address."
    }
    precondition {
      condition     = var.edge_exposure == "internal" || var.edge_mode == "loadbalancer"
      error_message = "edge_exposure = \"public\" applies to edge_mode = \"loadbalancer\" only. With ${var.edge_mode}, your own gateway or ingress decides where Autoheal is reachable."
    }
    precondition {
      condition     = !local.public_edge || !local.create_cluster
      error_message = "edge_exposure = \"public\" needs a brought cluster (existing_aks_cluster_id): existing_network.proxy_ip is a Standard static public IP that you make in the cluster's node resource group."
    }
    precondition {
      condition     = !local.public_edge || local.proxy_ip == "" || !local.proxy_ip_private
      error_message = "edge_exposure = \"public\": existing_network.proxy_ip (${local.proxy_ip}) must be a Standard static public IP in the cluster's node resource group, not a private address."
    }
    precondition {
      condition     = !local.public_edge || !local.dns_records_created || !local.dns_zone_private
      error_message = "edge_exposure = \"public\", but existing_dns_zone_id is a private DNS zone, so the internet cannot resolve ${var.hostname}. Use a public DNS zone, or set create_dns_records = false and make the records listed in required_dns_records."
    }
    precondition {
      condition     = local.create_vnet || local.public_path || !local.create_redis || try(var.existing_network.endpoint_subnet_id, "") != ""
      error_message = "We create Azure Managed Redis in a brought network, so existing_network.endpoint_subnet_id is required: Redis is reached only through a private endpoint. Set it, set existing_redis_id, or set redis_enabled = false."
    }
    precondition {
      condition     = local.create_vnet || !(local.pe_blob_enabled || local.pe_vault_enabled || local.pe_runtime_vault_enabled) || try(var.existing_network.endpoint_subnet_id, "") != ""
      error_message = "private_endpoints_enabled is true in a brought network, so existing_network.endpoint_subnet_id is required."
    }
    precondition {
      condition     = local.create_postgres || nonsensitive(var.postgres_admin_password != "")
      error_message = "existing_postgres_id is set, so postgres_admin_password is required. Azure cannot return a server's admin password; pass it as TF_VAR_postgres_admin_password from the pipeline's secret store."
    }
    precondition {
      condition     = lower(local.runtime_key_vault_name) != lower(local.key_vault_name)
      error_message = "The runtime Key Vault is the install vault (${local.key_vault_name}). It must be a separate vault: the api-server identity gets Key Vault Secrets Officer on it, which on the install vault would let it read every install secret. Set existing_runtime_key_vault_id to another vault, or leave it empty to create one."
    }
    precondition {
      condition     = !var.cmk_enabled || (local.create_key_vault && var.create_role_assignments)
      error_message = "cmk_enabled = true needs a Key Vault we create (no existing_key_vault_id) and create_role_assignments = true: the key lives in that vault and its encryption identity needs a role grant."
    }
  }
}

# --- Subscriptions -------------------------------------------------------------

# We create everything in subscription_id and read the brought cluster and its
# AKS subnet in the cluster's subscription. Every other brought ID is read
# through subscription_id by resource group and name, so it must be there.
locals {
  subscription_of = {
    for k, id in merge(
      {
        existing_resource_group_id    = var.existing_resource_group_id
        existing_postgres_id          = var.existing_postgres_id
        existing_redis_id             = var.existing_redis_id
        existing_storage_account_id   = var.existing_storage_account_id
        existing_key_vault_id         = var.existing_key_vault_id
        existing_runtime_key_vault_id = var.existing_runtime_key_vault_id
        existing_acr_id               = var.existing_acr_id
        existing_dns_zone_id          = var.existing_dns_zone_id
      },
      var.existing_network == null ? {} : {
        "existing_network.aks_subnet_id"      = var.existing_network.aks_subnet_id
        "existing_network.runner_subnet_id"   = var.existing_network.runner_subnet_id
        "existing_network.postgres_subnet_id" = var.existing_network.postgres_subnet_id
        "existing_network.endpoint_subnet_id" = var.existing_network.endpoint_subnet_id
      },
    ) : k => try(lower(split("/", id)[2]), "") if id != ""
  }

  # Brought IDs outside subscription_id, by kind. The AKS subnet is checked
  # against the cluster's subscription instead, and the DNS zone only when we
  # write records into it.
  subnets_outside = [
    for k in ["existing_network.runner_subnet_id", "existing_network.postgres_subnet_id", "existing_network.endpoint_subnet_id"] : k
    if lookup(local.subscription_of, k, lower(var.subscription_id)) != lower(var.subscription_id)
  ]
  resources_outside = [
    for k in ["existing_resource_group_id", "existing_postgres_id", "existing_redis_id", "existing_storage_account_id", "existing_key_vault_id", "existing_runtime_key_vault_id", "existing_acr_id"] : k
    if lookup(local.subscription_of, k, lower(var.subscription_id)) != lower(var.subscription_id)
  ]
}

resource "terraform_data" "validate_subscriptions" {
  lifecycle {
    precondition {
      condition     = lookup(local.subscription_of, "existing_network.aks_subnet_id", lower(local.cluster_subscription_id)) == lower(local.cluster_subscription_id)
      error_message = "existing_network.aks_subnet_id is in subscription ${lookup(local.subscription_of, "existing_network.aks_subnet_id", "")}, but the cluster is in ${local.cluster_subscription_id}. Use the AKS subnet of the cluster, in the cluster's subscription."
    }
    precondition {
      condition     = length(local.subnets_outside) == 0
      error_message = "${join(", ", local.subnets_outside)} must be in subscription_id (${var.subscription_id}): Azure puts a private endpoint, a Postgres delegated subnet and a VM network interface in the subscription of their VNet. Use subnets in that subscription. For a cluster in another subscription, leave the runner, Postgres and endpoint subnets empty and we create a VNet for them from network_cidr."
    }
    precondition {
      condition     = length(local.resources_outside) == 0
      error_message = "${join(", ", local.resources_outside)} must be in subscription_id (${var.subscription_id}): we read and write brought resources there. Only existing_aks_cluster_id and existing_network.aks_subnet_id may be in another subscription."
    }
    precondition {
      condition     = !local.dns_records_created || lookup(local.subscription_of, "existing_dns_zone_id", lower(var.subscription_id)) == lower(var.subscription_id)
      error_message = "existing_dns_zone_id is in another subscription than subscription_id (${var.subscription_id}), and we create the DNS records through subscription_id. Set create_dns_records = false and create the records in the required_dns_records output, or use a zone in subscription_id."
    }
  }
}

# --- The public path ------------------------------------------------------------

locals {
  # RFC 1918 ranges, which cannot be the public Temporal or proxy address.
  temporal_ip_private = anytrue([
    for r in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
    cidrhost("${local.temporal_ip}/${split("/", r)[1]}", 0) == split("/", r)[0]
  ])
  # A conditional, not &&: Terraform evaluates both sides of &&, and cidrhost
  # fails on an empty address.
  proxy_ip_private = local.proxy_ip == "" ? false : anytrue([
    for r in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
    cidrhost("${local.proxy_ip}/${split("/", r)[1]}", 0) == split("/", r)[0]
  ])
}

resource "terraform_data" "validate_public_path" {
  count = local.public_path ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.cluster_in_other_subscription
      error_message = "cluster_network_path = \"public\" is for a brought cluster in another subscription: existing_aks_cluster_id must be outside subscription_id. In one subscription the cluster and our VNet are already connected."
    }
    precondition {
      condition     = length(var.workload_egress_ip_ranges) > 0
      error_message = "cluster_network_path = \"public\" needs workload_egress_ip_ranges: the cluster's fixed public outbound addresses. Postgres and the Key Vaults let in only them."
    }
    precondition {
      condition     = !local.brought_workload_subnets
      error_message = "cluster_network_path = \"public\": leave existing_network.runner_subnet_id, postgres_subnet_id and endpoint_subnet_id empty. We create the runner's VNet with a NAT gateway, and the cluster's load balancers let in only that NAT address."
    }
    precondition {
      condition     = !local.temporal_public_lb || !local.temporal_ip_private
      error_message = "cluster_network_path = \"public\": existing_network.temporal_ip (${local.temporal_ip}) must be the Standard static public IP for Temporal in the cluster's node resource group, not a private address. If your firewall forwards Temporal to the cluster instead, set runner_temporal_address."
    }
    precondition {
      condition     = !local.temporal_via_firewall || local.temporal_ip_private
      error_message = "runner_temporal_address is set on cluster_network_path = \"public\", so your firewall forwards Temporal to existing_network.temporal_ip (${local.temporal_ip}): it must be a free private address in the AKS subnet, where the chart puts its internal load balancers."
    }
  }
}

# --- Reserved addresses inside a brought AKS subnet --------------------------

locals {
  brought_aks_prefix = local.create_network ? "" : try(data.azurerm_subnet.aks[0].address_prefixes[0], "")
  brought_aks_bits   = local.brought_aks_prefix == "" ? "" : split("/", local.brought_aks_prefix)[1]

  # An address is in the subnet when the network address of address/prefix equals
  # the subnet's network address. (cidrcontains needs Terraform 1.8.)
  # With a public Temporal load balancer the address is a public IP, not in the
  # subnet.
  temporal_ip_in_subnet = local.brought_aks_prefix == "" || local.temporal_public_lb ? true : (
    cidrhost(local.brought_aks_prefix, 0) == cidrhost("${local.temporal_ip}/${local.brought_aks_bits}", 0)
  )
  # A public proxy address is a public IP, not in the subnet.
  proxy_ip_in_subnet = local.brought_aks_prefix == "" || local.proxy_ip == "" || local.public_edge ? true : (
    cidrhost(local.brought_aks_prefix, 0) == cidrhost("${local.proxy_ip}/${local.brought_aks_bits}", 0)
  )
}

resource "terraform_data" "validate_addresses" {
  count = local.create_network ? 0 : 1

  lifecycle {
    precondition {
      condition     = local.temporal_ip_in_subnet
      error_message = "existing_network.temporal_ip (${local.temporal_ip}) is not inside the AKS subnet (${local.brought_aks_prefix}). Pick a free address in that subnet."
    }
    precondition {
      condition     = local.proxy_ip_in_subnet
      error_message = "existing_network.proxy_ip (${local.proxy_ip}) is not inside the AKS subnet (${local.brought_aks_prefix}). Pick a free address in that subnet."
    }
  }
}

# --- DNS ---------------------------------------------------------------------

resource "terraform_data" "validate_dns" {
  lifecycle {
    precondition {
      condition     = !var.create_dns_records || local.dns_target == "" || var.existing_dns_zone_id != ""
      error_message = "create_dns_records is true but existing_dns_zone_id is empty. Set existing_dns_zone_id to the DNS zone that holds ${var.hostname}, or set create_dns_records = false and create the records listed in the required_dns_records output."
    }
    precondition {
      condition = !local.dns_records_created || alltrue([
        for h in values(local.hosts) : h == local.dns_zone_name || endswith(h, ".${local.dns_zone_name}")
      ])
      error_message = "Every hostname must be inside the DNS zone ${local.dns_zone_name}: ${join(", ", values(local.hosts))}. Fix hostname, auth_hostname or auth_app_hostname, or set create_dns_records = false."
    }
  }
}

# --- Network paths to a Blob account and vault we create ----------------------

# Both are checked at plan time so a missing path surfaces here, not as a 403 mid
# apply or as pods that cannot read the vault. The runtime vault takes the same
# firewall settings as the install vault. Terraform writes nothing into it, so
# only the runtime path applies to it.
resource "terraform_data" "validate_reachability" {
  count = local.create_storage || local.create_key_vault || local.create_runtime_key_vault ? 1 : 0

  lifecycle {
    precondition {
      condition = (
        length(var.deployer_ip_ranges) > 0 ||
        ((!local.create_storage || var.storage_network_default_action == "Allow") &&
        (!local.create_key_vault || var.key_vault_network_default_action == "Allow"))
      )
      error_message = "No apply-time path to the Blob account or Key Vault. Terraform writes the vault entries from the apply host over the data plane. Set deployer_ip_ranges to the apply host's public egress CIDRs, or set storage_network_default_action and key_vault_network_default_action to \"Allow\" for a throwaway install. A private endpoint does not cover the apply host unless Terraform runs inside the VNet."
    }
    precondition {
      condition = (
        var.private_endpoints_enabled ||
        length(var.workload_egress_ip_ranges) > 0 ||
        ((!local.create_storage || var.storage_network_default_action == "Allow") &&
        (!(local.create_key_vault || local.create_runtime_key_vault) || var.key_vault_network_default_action == "Allow"))
      )
      error_message = "No runtime path to the Blob account or the Key Vaults. Pods reach them from the cluster's outbound address, not the apply host, so deployer_ip_ranges does not help them. Set private_endpoints_enabled = true, set workload_egress_ip_ranges to the cluster's outbound CIDRs, or set storage_network_default_action and key_vault_network_default_action to \"Allow\" for a throwaway install."
    }
  }
}

# --- Brought resources ---------------------------------------------------------

# Access to the vault is granted with Azure RBAC role assignments, which do
# nothing on an access-policy vault.
resource "terraform_data" "kv_rbac_guard" {
  count = local.create_key_vault ? 0 : 1

  lifecycle {
    precondition {
      condition     = try(data.azurerm_key_vault.existing[0].rbac_authorization_enabled, true) != false
      error_message = "Key Vault ${local.existing.key_vault.name} uses access policies. Autoheal grants vault access with Azure RBAC, which has no effect on an access-policy vault. Switch the vault to the Azure RBAC permission model."
    }
  }
}

resource "terraform_data" "runtime_kv_rbac_guard" {
  count = local.create_runtime_key_vault ? 0 : 1

  lifecycle {
    precondition {
      condition     = try(data.azurerm_key_vault.runtime_existing[0].rbac_authorization_enabled, true) != false
      error_message = "Key Vault ${local.existing.runtime_key_vault.name} (existing_runtime_key_vault_id) uses access policies. Autoheal grants the api-server identity access with Azure RBAC, which has no effect on an access-policy vault. Switch the vault to the Azure RBAC permission model."
    }
  }
}

# The Git Registry keeps one container per tenant and renames with Copy Blob and
# delete. Hierarchical namespace (ADLS Gen2) changes those semantics and cannot
# be turned off.
resource "terraform_data" "storage_hns_guard" {
  count = local.create_storage ? 0 : 1

  lifecycle {
    precondition {
      condition     = try(data.azurerm_storage_account.existing[0].is_hns_enabled, false) != true
      error_message = "Storage account ${local.existing.storage.name} has hierarchical namespace on (ADLS Gen2). Autoheal needs a flat namespace. Use an account with hierarchical namespace off."
    }
  }
}

# The chart authenticates with workload identity, which needs the OIDC issuer.
resource "terraform_data" "cluster_guard" {
  count = local.create_cluster ? 0 : 1

  lifecycle {
    precondition {
      condition     = try(data.azurerm_kubernetes_cluster.existing[0].oidc_issuer_enabled, true) != false
      error_message = "AKS cluster ${local.existing.aks.name} has no OIDC issuer. Turn it on, with workload identity: az aks update --enable-oidc-issuer --enable-workload-identity."
    }
  }
}

# The chart mounts the vault with the Secrets Store CSI driver and its Azure Key
# Vault provider. The AKS add-on is one way to run them; a cluster owner may
# install them another way, which the cluster resource does not show. So a
# cluster without the add-on gets a warning, not a stop. Without the driver the
# app apply stops on the missing SecretProviderClass kind.
check "keyvault_csi_driver" {
  assert {
    condition     = local.create_cluster || length(try(data.azurerm_kubernetes_cluster.existing[0].key_vault_secrets_provider, [{}])) > 0
    error_message = "AKS cluster ${try(local.existing.aks.name, "")} does not have the Key Vault secrets provider add-on. The chart needs the Secrets Store CSI driver with the Azure Key Vault provider. If the cluster runs them from another install, ignore this. Otherwise turn the add-on on: az aks enable-addons --addons azure-keyvault-secrets-provider."
  }
}

resource "terraform_data" "postgres_guard" {
  count = local.create_postgres ? 0 : 1

  lifecycle {
    precondition {
      condition     = try(tonumber(data.azurerm_postgresql_flexible_server.existing[0].version) >= 15, true)
      error_message = "Postgres server ${local.existing.postgres.name} runs version ${try(data.azurerm_postgresql_flexible_server.existing[0].version, "unknown")}. Autoheal needs version 15 or later."
    }
  }
}
