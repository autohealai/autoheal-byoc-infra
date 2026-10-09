# Autoheal BYOC — Azure Blob storage

Storage account + private container for attachments / knowledge-base objects in a
BYOC-on-AKS Autoheal install. The app reaches it keyless via the app workload
identity (Storage Blob Data Contributor, granted in
`modules/azure/workload-identity`); no account key is stored anywhere.

The AWS analogue is `modules/aws/s3`. Account names reject dashes and cap at 24
characters, so the module derives a sanitized name from the label id (override
available). Naming and tags follow the repo's null-label convention (see
`label.tf` and [docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the account lands in | — |
| `location` | Azure region | — |
| `account_name_override` | force an exact account name (else sanitized from label id) | `""` |
| `container_name` | blob container | `attachments` |
| `account_tier` | storage tier | `Standard` |
| `account_replication_type` | replication | `LRS` |

### Key outputs

| Name | Description |
|------|-------------|
| `account_name` | account name — maps to the contract `object_store` |
| `account_id` | account resource id |
| `blob_endpoint` | primary blob endpoint URL |
| `container_name` | container name |
<!-- END_TF_DOCS -->
