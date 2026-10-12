# Dedicated, least-scoped identity for the External Secrets Operator (ESO) on AKS.
# The AWS analogue is the IAM-role + Pod-Identity half of modules/byoc-eso-install:
# ESO gets its OWN identity (not the app's, not the node's) that may read ONLY this
# install's Key Vault, and nothing else.
#
# What this module does (cloud primitives only):
#   - a user-assigned identity for the ESO controller
#   - a federated credential binding it to the ESO controller ServiceAccount
#     (default external-secrets/external-secrets) via the AKS OIDC issuer
#   - a single "Key Vault Secrets User" role assignment on the install's Key Vault
#
# What it deliberately does NOT do: install the ESO operator, create the
# ClusterSecretStore, or declare ExternalSecrets. Those are in-cluster objects.
# This repo is pure cloud-infra (no helm/kubernetes providers) shipped as one
# composition per apply, so installing the operator here would mean configuring a
# helm/kubernetes provider from the cluster resource's own output (a Terraform
# anti-pattern) with no unit-layering to split it. The app/install layer
# (install-aks.sh / the Helm chart) owns those objects and consumes this module's
# outputs: client_id -> the ESO controller SA's azure.workload.identity/client-id
# annotation, tenant_id + the Key Vault vault_uri -> the ClusterSecretStore
# (provider.azurekv, authType WorkloadIdentity).
#
# Naming and tags come from the null-label base (module.this); see label.tf.

resource "azurerm_user_assigned_identity" "eso" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags
}

# Bind the identity to the ESO controller ServiceAccount. ESO impersonates this SA
# token to read Key Vault; the ClusterSecretStore's serviceAccountRef points here.
resource "azurerm_federated_identity_credential" "eso" {
  name                = "${var.eso_namespace}-${var.eso_service_account}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.eso.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.eso_namespace}:${var.eso_service_account}"
}

# Read-only access to exactly this install's Key Vault. Secrets User is the
# data-plane read role (list + get secret values); it grants nothing on keys,
# certificates, or vault management.
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.eso.principal_id
}
