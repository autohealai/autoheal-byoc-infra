# Autoheal BYOC: AWS S3 bucket

One S3 bucket for Autoheal data (attachments, artifacts, the Git Registry) in a
BYOC-on-EKS install. Pods reach it through an EKS Pod Identity role, so no access
keys are stored.

Always on: bucket owner enforced (ACLs off), all four public access blocks, and a
bucket policy that denies requests not made over TLS, merged with any additional
policy from the caller. Default encryption is SSE-KMS with an S3 Bucket Key when
`kms_key_arn` is set, SSE-S3 otherwise. Versioning, CORS rules, lifecycle rules
and server access logging are configurable.

The Azure analogue is `modules/azure/blob`. Tags follow the repo's null-label
convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)); the bucket name is
passed in full because bucket names are global.

## Notes

- **KMS key policy.** With SSE-KMS, every role that reads or writes objects needs
  `kms:Decrypt` and `kms:GenerateDataKey` on the key, in addition to its S3
  permissions.
- **Bucket policy.** `additional_policy_json` is merged before the
  `DenyInsecureTransport` statement; its statement Sids must be unique, and a
  statement named `DenyInsecureTransport` is replaced by the module one.
- **Access logs.** The target bucket must allow the S3 logging service
  (`logging.s3.amazonaws.com`) to write to it and must use SSE-S3, since server
  access logs cannot be delivered to a bucket with SSE-KMS default encryption.
- **Destroy.** A bucket that holds objects is only deleted when
  `force_destroy = true`.

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
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_cors_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_cors_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_log_bucket"></a> [access\_log\_bucket](#input\_access\_log\_bucket) | Bucket that receives server access logs. Empty turns access logging off. Pass a name known at plan time (a variable or this module's bucket\_id output), since it decides whether the logging configuration exists. | `string` | `""` | no |
| <a name="input_access_log_prefix"></a> [access\_log\_prefix](#input\_access\_log\_prefix) | Key prefix for the access logs in access\_log\_bucket, for example "s3/<bucket>/". | `string` | `""` | no |
| <a name="input_additional_policy_json"></a> [additional\_policy\_json](#input\_additional\_policy\_json) | IAM policy JSON merged into the bucket policy, ahead of the DenyInsecureTransport statement. A statement with the Sid DenyInsecureTransport is replaced by the module one. | `string` | `""` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_bucket"></a> [bucket](#input\_bucket) | Full bucket name. Bucket names are global across all AWS accounts, so include something unique such as the account ID. | `string` | n/a | yes |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_cors_rules"></a> [cors\_rules](#input\_cors\_rules) | CORS rules, for example to let a browser upload with presigned URLs (PUT, GET, HEAD from the app origin, exposing ETag). Empty means no CORS configuration. | <pre>list(object({<br/>    allowed_methods = list(string)<br/>    allowed_origins = list(string)<br/>    allowed_headers = optional(list(string), ["*"])<br/>    expose_headers  = optional(list(string), [])<br/>    max_age_seconds = optional(number, 3000)<br/>  }))</pre> | `[]` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Let a destroy delete the bucket even when it holds objects. Keep false for a real install. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for default encryption (SSE-KMS with an S3 Bucket Key). Empty uses SSE-S3 (AES256). | `string` | `""` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | Lifecycle rules. Each rule applies to objects under prefix (empty means the whole bucket); a day count of 0 leaves that action off. The default removes incomplete multipart uploads after 1 day. Empty means no lifecycle configuration. | <pre>list(object({<br/>    id                                     = string<br/>    enabled                                = optional(bool, true)<br/>    prefix                                 = optional(string, "")<br/>    expiration_days                        = optional(number, 0)<br/>    noncurrent_version_expiration_days     = optional(number, 0)<br/>    abort_incomplete_multipart_upload_days = optional(number, 0)<br/>  }))</pre> | <pre>[<br/>  {<br/>    "abort_incomplete_multipart_upload_days": 1,<br/>    "id": "abort-incomplete-multipart"<br/>  }<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | Keep previous versions of overwritten and deleted objects. Turning it off later suspends versioning; existing versions stay. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | Bucket ARN. |
| <a name="output_bucket_id"></a> [bucket\_id](#output\_bucket\_id) | Bucket name. Known at plan time, so it can feed another bucket's access\_log\_bucket. |
| <a name="output_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#output\_bucket\_regional\_domain\_name) | Regional domain name (<bucket>.s3.<region>.amazonaws.com), for clients and presigned URLs that must hit the bucket's region. |
<!-- END_TF_DOCS -->
