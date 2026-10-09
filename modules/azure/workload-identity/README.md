# Autoheal BYOC — Azure Workload Identity

User-assigned identity federated to the app's Kubernetes service accounts (via the
AKS OIDC issuer), so pods get Entra tokens with no stored credentials. Role
assignments grant exactly what the app needs: Key Vault Secrets User (ESO), Blob
Data Contributor, and optionally AcrPull.

The AWS analogue is EKS Pod Identity / IRSA. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the identity lands in | — |
| `location` | Azure region | — |
| `oidc_issuer_url` | AKS OIDC issuer (`aks` output `oidc_issuer_url`) | — |
| `federated_service_accounts` | `[{namespace, service_account}]` to federate | — |
| `key_vault_id` / `kv_role_enabled` | grant Key Vault Secrets User | `""` / `true` |
| `storage_account_id` / `blob_role_enabled` | grant Storage Blob Data Contributor | `""` / `true` |
| `acr_id` | grant AcrPull (empty skips) | `""` |

### Key outputs

| Name | Description |
|------|-------------|
| `client_id` | client id for the SA annotation — maps to the contract `runner_identity` |
| `principal_id` | principal (object) id for role assignments |
| `identity_id` | identity resource id |
<!-- END_TF_DOCS -->
