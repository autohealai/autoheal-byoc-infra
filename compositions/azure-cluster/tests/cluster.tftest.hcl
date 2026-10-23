# Plans of compositions/azure-cluster against mocked providers: the federated
# credentials it makes, the cluster details it outputs, and the cluster checks.
# Nothing here reaches Azure. (OpenTofu needs every attribute of a mocked object.)

mock_provider "azurerm" {}

mock_provider "azurerm" {
  alias = "cluster"

  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      oidc_issuer_enabled = true
      oidc_issuer_url     = "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
      kube_config = [{
        host                   = "https://acme-aks.hcp.eastus2.azmk8s.io:443"
        cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
        client_certificate     = ""
        client_key             = ""
        password               = ""
        username               = ""
      }]
      key_vault_secrets_provider = [{
        secret_rotation_enabled  = false
        secret_rotation_interval = "2m"
        secret_identity          = []
      }]
    }
  }
}

variables {
  cluster = {
    cloud           = "azure"
    name            = "acme-aks"
    resource_group  = "rg-acme-aks"
    subscription_id = "22222222-2222-2222-2222-222222222222"
    endpoint        = ""
    ca_certificate  = ""
  }
  federation = {
    subscription_id = "33333333-3333-3333-3333-333333333333"
    identities = {
      secrets = {
        identity_id      = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acme-prod-autoheal-secrets"
        service_accounts = [{ namespace = "autoheal", service_account = "autoheal-hooks" }]
      }
      api_server = {
        identity_id      = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acme-prod-autoheal-api-server"
        service_accounts = [{ namespace = "autoheal", service_account = "api-server-go" }]
      }
      agents_worker = {
        identity_id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acme-prod-autoheal-agents-worker"
        service_accounts = [
          { namespace = "autoheal", service_account = "agents-py-http" },
          { namespace = "autoheal", service_account = "agents-py-worker" },
        ]
      }
    }
  }
}

run "federates_each_service_account" {
  command = plan

  assert {
    condition = toset(keys(azurerm_federated_identity_credential.this)) == toset([
      "secrets/autoheal-autoheal-hooks",
      "api_server/autoheal-api-server-go",
      "agents_worker/autoheal-agents-py-http",
      "agents_worker/autoheal-agents-py-worker",
    ])
    error_message = "One federated credential per identity and service account."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["agents_worker/autoheal-agents-py-worker"].subject == "system:serviceaccount:autoheal:agents-py-worker"
    error_message = "The subject is the service account."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["agents_worker/autoheal-agents-py-worker"].name == "autoheal-agents-py-worker"
    error_message = "The credential name is <namespace>-<service account>, as compositions/azure names it."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["secrets/autoheal-autoheal-hooks"].issuer == "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
    error_message = "The issuer is the cluster's OIDC issuer."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["secrets/autoheal-autoheal-hooks"].user_assigned_identity_id == var.federation.identities.secrets.identity_id
    error_message = "The credential belongs to the identity."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["api_server/autoheal-api-server-go"].audience == tolist(["api://AzureADTokenExchange"])
    error_message = "The audience is the Entra token exchange."
  }

  assert {
    condition = output.cluster == {
      cloud           = "azure"
      name            = "acme-aks"
      resource_group  = "rg-acme-aks"
      subscription_id = "22222222-2222-2222-2222-222222222222"
      endpoint        = "https://acme-aks.hcp.eastus2.azmk8s.io:443"
      ca_certificate  = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
    }
    error_message = "The cluster output carries the endpoint and CA certificate read from the cluster."
  }

  assert {
    condition     = length(output.federated_credentials) == 4 && contains(output.federated_credentials, "id-acme-prod-autoheal-secrets: autoheal-autoheal-hooks (system:serviceaccount:autoheal:autoheal-hooks)")
    error_message = "federated_credentials lists each credential."
  }
}

run "other_namespace" {
  command = plan

  variables {
    federation = {
      subscription_id = "33333333-3333-3333-3333-333333333333"
      identities = {
        api_server = {
          identity_id      = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acme-prod-autoheal-api-server"
          service_accounts = [{ namespace = "acme-autoheal", service_account = "api-server-go" }]
        }
      }
    }
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["api_server/acme-autoheal-api-server-go"].subject == "system:serviceaccount:acme-autoheal:api-server-go"
    error_message = "The namespace comes from the federation input."
  }
}

run "no_oidc_issuer_is_rejected" {
  command = plan

  override_data {
    target = data.azurerm_kubernetes_cluster.this
    values = {
      oidc_issuer_enabled = false
      oidc_issuer_url     = ""
      kube_config = [{
        host                   = "https://acme-aks.hcp.eastus2.azmk8s.io:443"
        cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
        client_certificate     = ""
        client_key             = ""
        password               = ""
        username               = ""
      }]
      key_vault_secrets_provider = [{
        secret_rotation_enabled  = false
        secret_rotation_interval = "2m"
        secret_identity          = []
      }]
    }
  }

  expect_failures = [terraform_data.cluster_guard]
}

run "missing_csi_addon_warns" {
  command = plan

  override_data {
    target = data.azurerm_kubernetes_cluster.this
    values = {
      oidc_issuer_enabled = true
      oidc_issuer_url     = "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
      kube_config = [{
        host                   = "https://acme-aks.hcp.eastus2.azmk8s.io:443"
        cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
        client_certificate     = ""
        client_key             = ""
        password               = ""
        username               = ""
      }]
      key_vault_secrets_provider = []
    }
  }

  expect_failures = [check.keyvault_csi_driver]

  assert {
    condition     = length(azurerm_federated_identity_credential.this) == 4
    error_message = "A missing add-on warns; the credentials are still planned."
  }
}

run "null_federation_is_rejected" {
  command = plan

  variables {
    federation = null
  }

  expect_failures = [var.federation]
}

run "bad_identity_id_is_rejected" {
  command = plan

  variables {
    federation = {
      subscription_id = "33333333-3333-3333-3333-333333333333"
      identities = {
        secrets = {
          identity_id      = "id-acme-prod-autoheal-secrets"
          service_accounts = [{ namespace = "autoheal", service_account = "autoheal-hooks" }]
        }
      }
    }
  }

  expect_failures = [var.federation]
}
