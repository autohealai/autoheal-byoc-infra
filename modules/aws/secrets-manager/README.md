# Autoheal BYOC — AWS Secrets Manager

Secrets Manager storage for a BYOC-on-EKS Autoheal install. Creates one secret per
entry in `secrets` under a shared prefix (e.g. `tenants/avid/<key>`). The app reads
them through its IRSA role (`modules/aws/irsa`), which is granted `GetSecretValue`
on `<prefix>/*` — this module stores secrets, it does not grant read access.

The Azure analogue is `modules/azure/keyvault`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

> Secret values land in Terraform state. Seed only what the app needs and pass
> values through sensitive composition inputs; never hard-code real secrets here.

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     Module-specific inputs are in variables.tf; label inputs come from label.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `secret_prefix` | prefix each secret is created under, e.g. `tenants/avid` | (required) |
| `secrets` | map of key -> secret string (sensitive) | `{}` |
| `recovery_window_in_days` | retention before permanent delete | `7` |

### Key outputs

| Name | Description |
|------|-------------|
| `secret_store_uri` | prefix ARN — maps to the contract `secret_store_uri` |
| `secret_arns` | map of key -> full secret ARN |
<!-- END_TF_DOCS -->
