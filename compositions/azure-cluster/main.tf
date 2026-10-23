# The cluster step for a brought AKS cluster. compositions/azure never reads the
# cluster, so it needs no access to it. This composition, run after that one and
# by someone who may read the cluster, does the cluster side:
#
#   - reads the cluster (Azure Kubernetes Service Cluster User Role), for its
#     OIDC issuer, API endpoint and CA certificate;
#   - checks that the OIDC issuer is on, and warns when the Key Vault secrets
#     provider add-on is off;
#   - federates each Autoheal identity to the chart's service accounts through
#     that issuer, so pods get Entra tokens with no stored credential;
#   - outputs the cluster connection details for compositions/app.
#
# The federated credentials are created in the identities' subscription, the
# subscription of compositions/azure. Nothing is created in the cluster's.

data "azurerm_kubernetes_cluster" "this" {
  provider            = azurerm.cluster
  name                = var.cluster.name
  resource_group_name = var.cluster.resource_group
}

locals {
  oidc_issuer_url = data.azurerm_kubernetes_cluster.this.oidc_issuer_url

  # One credential per identity and service account. The name matches the one
  # compositions/azure gives a cluster it creates, and the one infra 3.x gave a
  # brought cluster, so import_federated_credentials finds them.
  federated_credentials = merge([
    for key, identity in var.federation.identities : {
      for sa in identity.service_accounts : "${key}/${sa.namespace}-${sa.service_account}" => {
        identity_id = identity.identity_id
        name        = "${sa.namespace}-${sa.service_account}"
        subject     = "system:serviceaccount:${sa.namespace}:${sa.service_account}"
      }
    }
  ]...)
}

resource "azurerm_federated_identity_credential" "this" {
  for_each = local.federated_credentials

  name                      = each.value.name
  user_assigned_identity_id = each.value.identity_id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.oidc_issuer_url
  subject                   = each.value.subject

  depends_on = [terraform_data.cluster_guard]
}

import {
  for_each = var.import_federated_credentials ? local.federated_credentials : {}
  to       = azurerm_federated_identity_credential.this[each.key]
  id       = "${each.value.identity_id}/federatedIdentityCredentials/${each.value.name}"
}

# The chart authenticates with workload identity, which needs the OIDC issuer.
resource "terraform_data" "cluster_guard" {
  lifecycle {
    precondition {
      condition     = data.azurerm_kubernetes_cluster.this.oidc_issuer_enabled && local.oidc_issuer_url != ""
      error_message = "AKS cluster ${var.cluster.name} has no OIDC issuer. Turn it on, with workload identity: az aks update --enable-oidc-issuer --enable-workload-identity."
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
    condition     = length(data.azurerm_kubernetes_cluster.this.key_vault_secrets_provider) > 0
    error_message = "AKS cluster ${var.cluster.name} does not have the Key Vault secrets provider add-on. The chart needs the Secrets Store CSI driver with the Azure Key Vault provider. If the cluster runs them from another install, ignore this. Otherwise turn the add-on on: az aks enable-addons --addons azure-keyvault-secrets-provider."
  }
}
