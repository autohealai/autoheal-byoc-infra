# State moves from v1. Both v1 compositions upgrade into this one:
#
#   compositions/azure-byoc          (created everything)
#   compositions/azure-byoc-connect  (read the customer's resources)
#
# Each building block gained a count (create or bring), so its v1 address moves
# to index 0. Nothing here destroys or replaces the cluster, the Postgres server,
# the storage account or the vault. The upgrade notes in CHANGELOG.md list the
# inputs to set so the plan stays that way (storage_container_name,
# create_registry, network_cidr and the renamed sizing inputs).

# --- compositions/azure-byoc ---------------------------------------------------

moved {
  from = azurerm_resource_group.this
  to   = azurerm_resource_group.this[0]
}

moved {
  from = random_password.postgres
  to   = random_password.postgres[0]
}

moved {
  from = module.vnet
  to   = module.vnet[0]
}

moved {
  from = module.aks
  to   = module.aks[0]
}

moved {
  from = module.postgres
  to   = module.postgres[0]
}

moved {
  from = module.blob
  to   = module.blob[0]
}

moved {
  from = module.keyvault
  to   = module.keyvault[0]
}

moved {
  from = module.acr
  to   = module.acr[0]
}

# --- Both ----------------------------------------------------------------------

# v1 had one app identity and one External Secrets identity. The External Secrets
# identity becomes the secrets identity read by the CSI driver; the app identity
# becomes the api-server identity. Their names change, so both are replaced with
# new client IDs. The chart reads the new IDs from autoheal_values.
moved {
  from = module.eso_identity
  to   = module.secrets_identity
}

moved {
  from = module.workload_identity
  to   = module.api_server_identity
}

# --- compositions/azure-byoc-connect ---------------------------------------------

moved {
  from = terraform_data.kv_rbac_guard
  to   = terraform_data.kv_rbac_guard[0]
}

moved {
  from = terraform_data.storage_hns_guard
  to   = terraform_data.storage_hns_guard[0]
}

# v1 seeded connection entries (redis-host, redis-port, redis-password,
# postgres-host, postgres-user) for External Secrets. 2.0 writes its own entries
# under new names (secrets.tf). Forget the old ones without deleting them, so a
# running v1 install keeps working until the chart upgrade; delete them by hand
# afterwards. The v1 entries seeded by the key vault module are forgotten the
# same way inside modules/azure/keyvault.
removed {
  from = azurerm_key_vault_secret.seed

  lifecycle {
    destroy = false
  }
}
