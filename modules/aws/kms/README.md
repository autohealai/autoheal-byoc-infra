# Autoheal BYOC - AWS KMS key

One customer managed KMS key (symmetric, encrypt and decrypt) with an alias,
automatic rotation and a key policy built from plain inputs. The other AWS
modules take its ARN to encrypt Kubernetes Secrets, EBS volumes, Aurora,
ElastiCache, S3, Secrets Manager and CloudWatch log groups.

The key policy always starts with the root statement for the current account, so
IAM policies can grant use of the key and the account cannot lock itself out.
Optional statements follow:

- `key_administrator_arns`: manage the key (policy, rotation, deletion), not use it.
- `key_user_arns`: encrypt and decrypt, and create grants for AWS resources only
  (`kms:GrantIsForAWSResource`).
- `cloudwatch_logs_enabled`: the regional CloudWatch Logs service principal, limited
  by the `kms:EncryptionContext:aws:logs:arn` condition to log groups in this
  account and region.
- `additional_policy_statements`: extra statements in IAM JSON shape, appended last.

A statement is added only when its input is non-empty. List lengths are known at
plan time even when the ARNs inside them come from the same apply, so the policy
always plans. Every principal in the policy must exist when it is applied, or KMS
rejects the policy.

The Azure analogue is a Key Vault key. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

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
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_policy_statements"></a> [additional\_policy\_statements](#input\_additional\_policy\_statements) | Extra IAM policy statement objects appended to the key policy, written as in IAM JSON (Sid, Effect, Principal, Action, Resource, Condition), e.g. [{ Sid = "AllowAcmeRole", Effect = "Allow", Principal = { AWS = "arn:aws:iam::111122223333:role/acme" }, Action = ["kms:Decrypt"], Resource = "*" }]. | `any` | `[]` | no |
| <a name="input_alias"></a> [alias](#input\_alias) | Key alias including the 'alias/' prefix. Empty uses 'alias/<label id>'. | `string` | `""` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_cloudwatch_logs_enabled"></a> [cloudwatch\_logs\_enabled](#input\_cloudwatch\_logs\_enabled) | Let the CloudWatch Logs service use the key for log groups in this account and region (needed when a log group sets kms\_key\_id to this key). | `bool` | `false` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Days KMS waits before deleting the key after it is scheduled for deletion (7-30). The key can be recovered during this window. | `number` | `30` | no |
| <a name="input_description"></a> [description](#input\_description) | What the key protects, shown in the KMS console, e.g. 'Autoheal acme-prod data at rest'. | `string` | n/a | yes |
| <a name="input_enable_key_rotation"></a> [enable\_key\_rotation](#input\_enable\_key\_rotation) | Rotate the key material automatically every rotation\_period\_in\_days. Old material is kept, so existing data stays readable. | `bool` | `true` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_key_administrator_arns"></a> [key\_administrator\_arns](#input\_key\_administrator\_arns) | IAM principal ARNs that may manage the key (policy, rotation, deletion) but not use it to encrypt or decrypt. Empty adds no statement; the account root statement still lets IAM policies grant access. | `list(string)` | `[]` | no |
| <a name="input_key_user_arns"></a> [key\_user\_arns](#input\_key\_user\_arns) | IAM principal ARNs that may use the key to encrypt and decrypt, and create grants for AWS services. Every principal must already exist when the policy is applied, or KMS rejects it. Empty adds no statement. | `list(string)` | `[]` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_rotation_period_in_days"></a> [rotation\_period\_in\_days](#input\_rotation\_period\_in\_days) | Days between automatic rotations (90-2560). Used only when enable\_key\_rotation is true. | `number` | `365` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | ARN of the alias. |
| <a name="output_alias_name"></a> [alias\_name](#output\_alias\_name) | Alias name, including the 'alias/' prefix. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | ARN of the KMS key. Pass this to resources that take a kms\_key\_id or kms\_key\_arn. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | ID (UUID) of the KMS key. |
<!-- END_TF_DOCS -->
