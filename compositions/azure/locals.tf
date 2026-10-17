# Derived values shared by the building-block files. Every create-or-bring
# decision is made here from plan-time inputs only (variables, never resource
# attributes), so count and for_each never depend on values known after apply.

data "azurerm_client_config" "current" {}

locals {
  # null-label id used by every module, e.g. acme-prod-autoheal.
  id = lower(join("-", compact([var.namespace, var.environment, var.name])))

  # --- Create or bring ------------------------------------------------------

  create_resource_group    = var.existing_resource_group_id == ""
  create_network           = var.existing_network == null
  create_cluster           = var.existing_aks_cluster_id == ""
  create_postgres          = var.existing_postgres_id == ""
  create_storage           = var.existing_storage_account_id == ""
  create_key_vault         = var.existing_key_vault_id == ""
  create_runtime_key_vault = var.existing_runtime_key_vault_id == ""
  create_registry          = var.existing_acr_id == "" && var.create_registry
  create_redis             = var.redis_enabled && var.existing_redis_id == ""

  redis_enabled = var.redis_enabled || var.existing_redis_id != ""
  acr_enabled   = local.create_registry || var.existing_acr_id != ""

  # A brought Redis is either Azure Managed Redis or Azure Cache for Redis.
  brought_redis_kind = var.existing_redis_id == "" ? "" : (
    lower(split("/", var.existing_redis_id)[7]) == "redisenterprise" ? "managed" : "cache"
  )

  # Brought IDs split into their parts. Azure IDs look like
  # /subscriptions/<sub>/resourceGroups/<rg>/providers/<ns>/<type>/<name>, so index
  # 4 is the resource group and index 8 the name. A subnet adds
  # /subnets/<subnet>, so index 8 is the VNet and index 10 the subnet.
  existing = {
    resource_group_name = local.create_resource_group ? "" : split("/", var.existing_resource_group_id)[4]
    aks = local.create_cluster ? null : {
      rg   = split("/", var.existing_aks_cluster_id)[4]
      name = split("/", var.existing_aks_cluster_id)[8]
    }
    postgres = local.create_postgres ? null : {
      rg   = split("/", var.existing_postgres_id)[4]
      name = split("/", var.existing_postgres_id)[8]
    }
    redis = var.existing_redis_id == "" ? null : {
      rg   = split("/", var.existing_redis_id)[4]
      name = split("/", var.existing_redis_id)[8]
    }
    storage = local.create_storage ? null : {
      rg   = split("/", var.existing_storage_account_id)[4]
      name = split("/", var.existing_storage_account_id)[8]
    }
    acr = var.existing_acr_id == "" ? null : {
      rg   = split("/", var.existing_acr_id)[4]
      name = split("/", var.existing_acr_id)[8]
    }
    key_vault = local.create_key_vault ? null : {
      rg   = split("/", var.existing_key_vault_id)[4]
      name = split("/", var.existing_key_vault_id)[8]
    }
    runtime_key_vault = local.create_runtime_key_vault ? null : {
      rg   = split("/", var.existing_runtime_key_vault_id)[4]
      name = split("/", var.existing_runtime_key_vault_id)[8]
    }
  }

  # --- Resource group -------------------------------------------------------

  resource_group_name = local.create_resource_group ? (
    var.resource_group_name != "" ? var.resource_group_name : "rg-${var.namespace}-${var.environment}-${var.name}"
  ) : local.existing.resource_group_name

  # --- Hostnames ------------------------------------------------------------

  hosts = {
    app     = var.hostname
    auth    = var.auth_hostname != "" ? var.auth_hostname : "auth.${var.hostname}"
    authApp = var.auth_app_hostname != "" ? var.auth_app_hostname : "auth-app.${var.hostname}"
  }

  # --- Subnets and reserved addresses ---------------------------------------

  # Subnet layout of the network we create. For a /16 this is the v1 layout:
  # AKS 10.60.0.0/20, Postgres 10.60.16.0/24, private endpoints 10.60.17.0/24,
  # runner 10.60.19.0/24.
  created_subnets = {
    aks      = cidrsubnet(var.network_cidr, 4, 0)
    postgres = cidrsubnet(var.network_cidr, 8, 16)
    endpoint = cidrsubnet(var.network_cidr, 8, 17)
    runner   = cidrsubnet(var.network_cidr, 8, 19)
  }

  # In a network we create, the reserved addresses are near the top of the AKS
  # subnet, away from the node addresses Azure hands out from the bottom. The last
  # address is reserved by Azure, so Temporal takes the third from the end and the
  # proxy the second from the end.
  temporal_ip = local.create_network ? cidrhost(local.created_subnets.aks, -3) : var.existing_network.temporal_ip
  proxy_ip = var.edge_mode != "loadbalancer" ? "" : (
    local.create_network ? cidrhost(local.created_subnets.aks, -2) : try(var.existing_network.proxy_ip, "")
  )

  # VNet ID of a brought network, from the AKS subnet ID.
  brought_vnet_id = local.create_network ? "" : join("/", slice(split("/", var.existing_network.aks_subnet_id), 0, 9))

  aks_subnet_id      = local.create_network ? module.vnet[0].subnet_aks_id : var.existing_network.aks_subnet_id
  runner_subnet_id   = local.create_network ? module.vnet[0].subnet_runner_id : var.existing_network.runner_subnet_id
  postgres_subnet_id = local.create_network ? module.vnet[0].subnet_db_id : var.existing_network.postgres_subnet_id
  endpoint_subnet_id = local.create_network ? module.vnet[0].subnet_pe_id : var.existing_network.endpoint_subnet_id

  # --- Private endpoints ----------------------------------------------------

  pe_blob_enabled  = var.private_endpoints_enabled && local.create_storage
  pe_vault_enabled = var.private_endpoints_enabled && local.create_key_vault
  # The runtime vault uses the same privatelink zone as the install vault.
  pe_runtime_vault_enabled = var.private_endpoints_enabled && local.create_runtime_key_vault

  # privatelink zones a brought network needs from us: one per private endpoint we
  # create whose zone the customer did not pass in existing_network.
  pe_zone_names = {
    blob  = "privatelink.blob.core.windows.net"
    vault = "privatelink.vaultcore.azure.net"
    redis = "privatelink.redis.azure.net"
  }
  pe_zones_needed = toset(compact([
    local.pe_blob_enabled ? "blob" : "",
    local.pe_vault_enabled || local.pe_runtime_vault_enabled ? "vault" : "",
    local.create_redis ? "redis" : "",
  ]))
  brought_network_zones = local.create_network ? toset([]) : toset([
    for k in local.pe_zones_needed : k if !contains(keys(var.existing_network.private_dns_zone_ids), k)
  ])
  pe_zone_ids = {
    for k in local.pe_zones_needed : k => (
      local.create_network ? (
        k == "blob" ? module.vnet[0].blob_private_dns_zone_id :
        k == "vault" ? module.vnet[0].vault_private_dns_zone_id :
        module.vnet[0].redis_private_dns_zone_id
        ) : (
        contains(keys(var.existing_network.private_dns_zone_ids), k)
        ? var.existing_network.private_dns_zone_ids[k]
        : azurerm_private_dns_zone.brought[k].id
      )
    )
  }

  # --- Customer-managed key -------------------------------------------------

  # Postgres needs a versioned key id; the storage account takes the versionless id
  # so it follows key rotation.
  cmk_key_vault_key_id             = var.cmk_enabled ? azurerm_key_vault_key.cmk[0].id : ""
  cmk_key_vault_key_versionless_id = var.cmk_enabled ? azurerm_key_vault_key.cmk[0].versionless_id : ""
  cmk_identity_id                  = var.cmk_enabled ? azurerm_user_assigned_identity.cmk[0].id : ""

  # --- Facts gathered from created or brought blocks -------------------------

  cluster_name = local.create_cluster ? module.aks[0].cluster_name : local.existing.aks.name
  cluster_rg   = local.create_cluster ? local.resource_group_name : local.existing.aks.rg
  cluster_id   = local.create_cluster ? module.aks[0].cluster_id : var.existing_aks_cluster_id
  oidc_issuer  = local.create_cluster ? module.aks[0].oidc_issuer_url : data.azurerm_kubernetes_cluster.existing[0].oidc_issuer_url

  postgres_host = local.create_postgres ? module.postgres[0].host : data.azurerm_postgresql_flexible_server.existing[0].fqdn
  postgres_admin_login = local.create_postgres ? module.postgres[0].administrator_login : (
    data.azurerm_postgresql_flexible_server.existing[0].administrator_login
  )

  storage_account_id   = local.create_storage ? module.blob[0].account_id : var.existing_storage_account_id
  storage_account_name = local.create_storage ? module.blob[0].account_name : local.existing.storage.name

  key_vault_id        = local.create_key_vault ? module.keyvault[0].key_vault_id : var.existing_key_vault_id
  key_vault_name      = local.create_key_vault ? module.keyvault[0].key_vault_name : local.existing.key_vault.name
  key_vault_tenant_id = local.create_key_vault ? data.azurerm_client_config.current.tenant_id : data.azurerm_key_vault.existing[0].tenant_id

  # The runtime vault we create is named like the install vault with -rt at the
  # end, cut so the name stays within Key Vault's 24 characters.
  runtime_key_vault_create_name = "${trimsuffix(substr(local.id, 0, 21), "-")}-rt"
  runtime_key_vault_id          = local.create_runtime_key_vault ? module.runtime_keyvault[0].key_vault_id : var.existing_runtime_key_vault_id
  runtime_key_vault_name        = local.create_runtime_key_vault ? module.runtime_keyvault[0].key_vault_name : local.existing.runtime_key_vault.name
  # api-server-go takes the vault URL with a trailing slash.
  runtime_key_vault_url = "${trimsuffix(local.create_runtime_key_vault ? module.runtime_keyvault[0].vault_uri : data.azurerm_key_vault.runtime_existing[0].vault_uri, "/")}/"
  runtime_key_vault_purge_protection_enabled = (
    var.runtime_key_vault_purge_protection_enabled != null ? var.runtime_key_vault_purge_protection_enabled : var.key_vault_purge_protection_enabled
  )

  acr_id   = local.create_registry ? module.acr[0].acr_id : var.existing_acr_id
  acr_name = local.create_registry ? module.acr[0].acr_name : (var.existing_acr_id == "" ? "" : local.existing.acr.name)
  # An ACR login server is always the lowercase registry name under azurecr.io,
  # so it is known at plan time for a created or a brought registry.
  acr_login_server = local.acr_enabled ? "${lower(local.acr_name)}.azurecr.io" : ""

  redis_host = !local.redis_enabled ? "" : (
    local.create_redis ? module.redis[0].hostname :
    local.brought_redis_kind == "managed" ? data.azurerm_managed_redis.existing[0].hostname :
    data.azurerm_redis_cache.existing[0].hostname
  )
  redis_port = !local.redis_enabled ? 0 : (
    local.create_redis ? module.redis[0].port :
    local.brought_redis_kind == "managed" ? try(data.azurerm_managed_redis.existing[0].default_database[0].port, 10000) :
    data.azurerm_redis_cache.existing[0].ssl_port
  )
  redis_access_key = !local.redis_enabled ? "" : (
    local.create_redis ? module.redis[0].primary_access_key :
    local.brought_redis_kind == "managed" ? try(data.azurerm_managed_redis.existing[0].default_database[0].primary_access_key, "") :
    data.azurerm_redis_cache.existing[0].primary_access_key
  )

  # --- DNS ------------------------------------------------------------------

  dns_zone_name    = var.existing_dns_zone_id == "" ? "" : lower(split("/", var.existing_dns_zone_id)[8])
  dns_zone_rg      = var.existing_dns_zone_id == "" ? "" : split("/", var.existing_dns_zone_id)[4]
  dns_zone_private = var.existing_dns_zone_id == "" ? false : lower(split("/", var.existing_dns_zone_id)[7]) == "privatednszones"

  # Where the three records point: the reserved proxy address in loadbalancer mode,
  # edge_address otherwise. Empty means the records are left to the customer.
  dns_target = var.edge_mode == "loadbalancer" ? local.proxy_ip : var.edge_address

  dns_records_created = var.create_dns_records && var.existing_dns_zone_id != "" && local.dns_target != ""

  # Relative record names inside the zone; "@" is the zone apex.
  dns_record_names = {
    for k, h in local.hosts : k => (h == local.dns_zone_name ? "@" : trimsuffix(h, ".${local.dns_zone_name}"))
  }
}
