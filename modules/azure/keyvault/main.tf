# Key Vault, RBAC mode. The AWS analogue is modules/aws/secrets-manager. In-cluster
# workloads read these secrets through the Key Vault CSI driver using a dedicated
# workload identity (modules/azure/secrets-identity grants it Key Vault Secrets
# User). The composition writes the secret entries itself, so it can write to a
# vault this module created or to one the customer brought.
#
# RBAC mode means the principal running Terraform needs a data-plane role to write
# secrets, so by default we grant the deployer Key Vault Secrets Officer. Azure RBAC
# propagation can lag a few seconds, so a first apply may need one retry if it races
# (documented, not worked around). Set deployer_role_enabled = false when the
# deployer cannot create role assignments and an admin grants the role instead.
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
  soft_delete_retention_days = var.soft_delete_retention_days
  tags                       = module.this.tags

  # Firewall: default-deny. The CSI driver reads secrets over a private endpoint, so
  # the public path stays closed. bypass=AzureServices admits trusted Azure platform services;
  # allowed_ip_ranges opens the apply host's public IP so the deployer can write
  # secrets over the data plane (RBAC-mode vaults enforce data-plane access, which
  # default_action=Deny would otherwise block). Set network_default_action=Allow
  # only for throwaway/playground vaults with no private endpoint.
  network_acls {
    default_action = var.network_default_action
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
}

resource "azurerm_role_assignment" "deployer" {
  count                = var.deployer_role_enabled ? 1 : 0
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployer_object_id
}

moved {
  from = azurerm_role_assignment.deployer
  to   = azurerm_role_assignment.deployer[0]
}

# v1 seeded secrets from this module. v2 writes all entries from the composition.
# Forget the v1 seed resources without deleting the secrets from the vault, so an
# upgrade never removes a value a running install still reads.
removed {
  from = azurerm_key_vault_secret.seed

  lifecycle {
    destroy = false
  }
}
