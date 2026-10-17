# Identity the Key Vault CSI driver uses to read this install's vault on AKS. The
# AWS analogue is the IAM role External Secrets Operator uses on EKS.
#
# What this module creates (cloud primitives only):
#   - a user-assigned identity
#   - one federated credential per chart ServiceAccount that mounts the
#     SecretProviderClass. With workload identity, the CSI driver requests a token
#     for the pod's own ServiceAccount, so every pod that mounts the vault needs its
#     ServiceAccount federated to this identity.
#   - "Key Vault Secrets User" on exactly this install's vault, unless the caller
#     sets role_assignment_enabled = false (the grant is then made by an
#     administrator and listed by the composition).
#
# It creates no in-cluster objects. The chart builds the SecretProviderClass from
# global.infra.keyVault and global.infra.identities.secrets (this module's
# client_id).
#
# Renamed from modules/azure/external-secrets in 2.0.0. The moved blocks below
# carry v1 state over; the identity name changes with the new attributes, so a v1
# install gets a new identity and client ID.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

resource "azurerm_user_assigned_identity" "this" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags
}

resource "azurerm_federated_identity_credential" "sa" {
  for_each = {
    for sa in var.service_accounts :
    "${sa.namespace}-${sa.service_account}" => sa
  }
  name                = each.key
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

# Read-only access to exactly this install's vault. Secrets User is the data-plane
# read role (list and get secret values); it grants nothing on keys, certificates
# or vault management. Gated on a plan-time bool, never on the vault id.
resource "azurerm_role_assignment" "kv_secrets_user" {
  count                = var.role_assignment_enabled ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

moved {
  from = azurerm_user_assigned_identity.eso
  to   = azurerm_user_assigned_identity.this
}

moved {
  from = azurerm_role_assignment.kv_secrets_user
  to   = azurerm_role_assignment.kv_secrets_user[0]
}
