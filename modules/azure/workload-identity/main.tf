# Entra Workload Identity for the app. The AWS analogue is EKS Pod Identity / IRSA.
# A user-assigned identity is federated to one or more Kubernetes service accounts
# (via the AKS OIDC issuer from modules/azure/aks), so pods get Entra tokens with
# no stored credentials. Role assignments give that identity exactly what the app
# needs: read secrets from Key Vault (for ESO), read/write Blob, optionally pull ACR.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

resource "azurerm_user_assigned_identity" "app" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags
}

resource "azurerm_federated_identity_credential" "sa" {
  for_each = {
    for sa in var.federated_service_accounts :
    "${sa.namespace}-${sa.service_account}" => sa
  }
  name                = each.key
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.app.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  count                = var.kv_role_enabled ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_role_assignment" "blob_contributor" {
  count                = var.blob_role_enabled ? 1 : 0
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.acr_id == "" ? 0 : 1
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}
