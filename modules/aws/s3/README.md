# Autoheal BYOC — AWS S3 (attachments)

S3 bucket for attachments / knowledge base for a BYOC-on-EKS Autoheal install.
Versioned, SSE-S3 encrypted, all public access blocked, noncurrent versions expired
after 90 days. The app reaches it via an IRSA role (`modules/aws/irsa`), so no static
keys are stored.

The Azure analogue is `modules/azure/blob`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     Module-specific inputs are in variables.tf; label inputs come from label.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `bucket_name_override` | force an exact bucket name | `""` (derive from label id) |
| `noncurrent_version_expiration_days` | expire old versions after N days | `90` |
| `enable_cors` / `cors_allowed_origins` | browser-upload CORS | `false` / `[]` |

### Key outputs

| Name | Description |
|------|-------------|
| `bucket_name` | bucket name — maps to the contract `object_store` |
| `bucket_arn` | bucket ARN (grant IRSA access on this) |
<!-- END_TF_DOCS -->
