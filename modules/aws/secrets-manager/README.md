# Autoheal BYOC: AWS Secrets Manager

Secrets Manager entries for a BYOC-on-EKS Autoheal install: one secret per entry
in `secret_names`, named `<name_prefix><entry>` and encrypted with the caller's
KMS key, with optional replicas in other regions. The app reads them through an
EKS Pod Identity role granted `GetSecretValue` on `arn_pattern`; this module
grants no access itself.

The Azure analogue is `modules/azure/keyvault`. Tags follow the repo's null-label
convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Notes

- **Names and values are separate.** `secret_names` decides which secrets exist
  and must be known at plan time. `secret_values` is sensitive and may hold
  values created in the same apply (for example a `random_password` result).
  Every name needs a value; extra keys in `secret_values` are ignored.
- **State.** Secret values are stored in Terraform state. Keep the state
  backend encrypted and access-controlled.
- **Changing a value** writes a new secret version and moves `AWSCURRENT` to it.
  Pods pick it up on their next read or restart.
- **KMS key policy.** Roles that read the secrets need `kms:Decrypt` on the key
  as well as `secretsmanager:GetSecretValue`.
- **Replicas.** Each replica uses the key from `replica_kms_key_arns` for its
  region. Without one, it uses the replica of `kms_key_arn` when that is a
  multi-Region key, otherwise the AWS managed key `aws/secretsmanager`.
  `arn_pattern` covers the primary region only.
- **Delete and recreate.** A deleted secret keeps its name for
  `recovery_window_in_days`. Use 0 for throwaway installs that are torn down
  and rebuilt under the same prefix.

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | ../../_shared/label | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_secretsmanager_secret.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN that encrypts the secrets. | `string` | n/a | yes |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every secret name, for example "acme-prod-autoheal/". Each secret is named <name\_prefix><entry>, and arn\_pattern grants access by this prefix, so end it with "/" or "-". | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_recovery_window_in_days"></a> [recovery\_window\_in\_days](#input\_recovery\_window\_in\_days) | Days a deleted secret can still be restored. 0 deletes it at once, which lets a secret with the same name be created again right away. | `number` | `30` | no |
| <a name="input_replica_kms_key_arns"></a> [replica\_kms\_key\_arns](#input\_replica\_kms\_key\_arns) | KMS key ARN per replica region. A region not in the map uses the replica of kms\_key\_arn when that is a multi-Region key (mrk-), otherwise the AWS managed key aws/secretsmanager in that region. | `map(string)` | `{}` | no |
| <a name="input_replica_regions"></a> [replica\_regions](#input\_replica\_regions) | Regions to replicate every secret to, for example ["us-east-1"]. Empty means no replicas. | `list(string)` | `[]` | no |
| <a name="input_secret_names"></a> [secret\_names](#input\_secret\_names) | Entry names, one secret each (for example "postgres-password"). Not sensitive: they decide which secrets exist and must be known at plan time. | `list(string)` | n/a | yes |
| <a name="input_secret_values"></a> [secret\_values](#input\_secret\_values) | Secret string per entry, keyed by the names in secret\_names. Values may come from resources created in the same apply. Keys not in secret\_names are ignored. Values are stored in Terraform state. | `map(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn_pattern"></a> [arn\_pattern](#output\_arn\_pattern) | ARN pattern that matches every secret under name\_prefix in this region, for GetSecretValue in an IAM policy. |
| <a name="output_name_prefix"></a> [name\_prefix](#output\_name\_prefix) | Prefix all secret names start with. |
| <a name="output_secret_arns"></a> [secret\_arns](#output\_secret\_arns) | Secret ARN per entry. AWS adds a random six-character suffix, so use arn\_pattern for IAM policies. |
| <a name="output_secret_names"></a> [secret\_names](#output\_secret\_names) | Full secret name (<name\_prefix><entry>) per entry. |
<!-- END_TF_DOCS -->
