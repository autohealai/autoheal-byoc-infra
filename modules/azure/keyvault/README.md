# Autoheal BYOC — Azure Key Vault

RBAC-mode Key Vault that holds the app secrets (generated PG password, etc.)
for a BYOC-on-AKS Autoheal install. ESO reads them via the app workload
identity (`modules/azure/workload-identity` grants Key Vault Secrets User).

The AWS analogue is `modules/aws/secrets-manager`. The deployer is granted Key
Vault Secrets Officer so the apply can seed secrets; RBAC propagation can lag a
few seconds on the very first apply. Naming and tags follow the repo's null-label
convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the vault lands in | — |
| `location` | Azure region | — |
| `tenant_id` | Entra tenant id | — |
| `deployer_object_id` | principal running Terraform (granted Secrets Officer) | — |
| `secrets` | name→value map to seed (sensitive) | `{}` |
| `name_override` | force an exact vault name (else label id, truncated 24) | `""` |
| `purge_protection_enabled` | enable purge protection (irreversible) | `false` |

### Key outputs

| Name | Description |
|------|-------------|
| `vault_uri` | vault URI — maps to the contract `secret_store_uri` |
| `key_vault_id`, `key_vault_name` | vault resource id / name |
<!-- END_TF_DOCS -->
