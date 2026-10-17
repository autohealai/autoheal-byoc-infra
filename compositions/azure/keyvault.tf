# Key Vault: the RBAC-mode vault we create, or the customer's vault read through a
# data source. secrets.tf writes the entries into whichever it is. The deployer
# needs Key Vault Secrets Officer to write them; we grant it unless
# create_role_assignments = false.
#
# Also the optional customer-managed key (CMK) that encrypts the Postgres server
# and storage account we create. It lives in the vault we create, so CMK needs a
# created vault (validation.tf).

module "keyvault" {
  source = "../../modules/azure/keyvault"
  count  = local.create_key_vault ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  resource_group_name        = local.rg
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  deployer_object_id         = data.azurerm_client_config.current.object_id
  deployer_role_enabled      = var.create_role_assignments
  purge_protection_enabled   = var.key_vault_purge_protection_enabled
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days

  # Default-deny firewall. The allow list covers the apply host (to write entries)
  # and the cluster's outbound addresses (when private endpoints are off).
  network_default_action = var.key_vault_network_default_action
  allowed_ip_ranges      = distinct(concat(var.deployer_ip_ranges, var.workload_egress_ip_ranges))
}

data "azurerm_key_vault" "existing" {
  count               = local.create_key_vault ? 0 : 1
  name                = local.existing.key_vault.name
  resource_group_name = local.existing.key_vault.rg
}

# The deployer writes entries into a brought vault. Scoped to that vault only.
resource "azurerm_role_assignment" "deployer_kv" {
  count                = !local.create_key_vault && var.create_role_assignments ? 1 : 0
  scope                = var.existing_key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# --- Customer-managed key ---------------------------------------------------

# A dedicated identity holds the encryption role; the RSA key is created in the
# vault we create. Azure RBAC propagation can lag, so a first apply may need one
# retry if the key creation races the deployer's Crypto Officer grant.
resource "azurerm_user_assigned_identity" "cmk" {
  count               = var.cmk_enabled ? 1 : 0
  name                = "id-${var.namespace}-${var.environment}-${var.name}-cmk"
  resource_group_name = local.rg
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "cmk_deployer" {
  count                = var.cmk_enabled ? 1 : 0
  scope                = module.keyvault[0].key_vault_id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "cmk_encryptor" {
  count                = var.cmk_enabled ? 1 : 0
  scope                = module.keyvault[0].key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.cmk[0].principal_id
}

resource "azurerm_key_vault_key" "cmk" {
  count        = var.cmk_enabled ? 1 : 0
  name         = "${var.namespace}-${var.environment}-${var.name}-cmk"
  key_vault_id = module.keyvault[0].key_vault_id
  key_type     = "RSA"
  key_size     = 3072
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  depends_on = [azurerm_role_assignment.cmk_deployer]

  lifecycle {
    precondition {
      condition     = var.key_vault_purge_protection_enabled
      error_message = "cmk_enabled = true requires key_vault_purge_protection_enabled = true: Azure only uses a customer-managed key from a vault with purge protection on."
    }
  }
}
