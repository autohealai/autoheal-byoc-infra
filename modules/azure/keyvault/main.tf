# Key Vault, RBAC mode. The AWS analogue is modules/aws/secrets-manager. ESO reads
# these secrets via its own dedicated, least-scoped identity (modules/azure/
# external-secrets grants that identity Key Vault Secrets User — NOT the app
# identity). The ClusterSecretStore + ExternalSecrets are in-cluster objects wired
# by the app/install layer, which consumes the composition's eso_* outputs.
#
# RBAC mode means the principal running Terraform needs a data-plane role to seed
# secrets, so we grant the deployer Key Vault Secrets Officer. The seed secrets
# depend on that assignment; Azure RBAC propagation can lag a few seconds, so a
# first apply may need one retry if it races (documented, not worked around).
#
# Vault names allow dashes but cap at 24 chars, so we truncate the label id;
# name_override forces an exact name when a fixed convention is required.

locals {
  vault_name = var.name_override != "" ? var.name_override : substr(module.this.id, 0, 24)
}

resource "azurerm_key_vault" "this" {
  name                       = local.vault_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = 7
  tags                       = module.this.tags
}

resource "azurerm_role_assignment" "deployer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployer_object_id
}

# for_each over the secret NAMES (not the sensitive map itself — a sensitive value
# cannot key resource instances). Names are not secret; values stay sensitive.
resource "azurerm_key_vault_secret" "seed" {
  for_each     = nonsensitive(toset(keys(var.secrets)))
  name         = each.value
  value        = var.secrets[each.value]
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.deployer]
}
