# Autoheal BYOC — AWS ECR

ECR repositories for a BYOC-on-EKS Autoheal install. ECR is an account-level
registry (`<account>.dkr.ecr.<region>.amazonaws.com`); this module creates the
per-service repositories under it and a lifecycle policy that prunes old images.
Nodes pull via the node-group role (wired in `modules/aws/eks`); the runner pulls
via its instance profile (`modules/aws/runner-asg`).

The Azure analogue is `modules/azure/acr` (one registry resource) — here the
"registry" is the account endpoint, exposed as `registry_url`. Naming and tags
follow the repo's null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | ../../_shared/label | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_encryption_type"></a> [encryption\_type](#input\_encryption\_type) | AES256 (S3-managed) or KMS. kms\_key\_arn is used only when KMS. | `string` | `"AES256"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_image_tag_mutability"></a> [image\_tag\_mutability](#input\_image\_tag\_mutability) | IMMUTABLE forbids overwriting a tag; MUTABLE allows floating tags like 'latest'. | `string` | `"MUTABLE"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN when encryption\_type is KMS. Empty uses the AWS-managed ECR key. | `string` | `""` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_max_image_count"></a> [max\_image\_count](#input\_max\_image\_count) | Keep at most this many tagged images per repository; older ones expire. | `number` | `100` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'avid'. | `string` | `null` | no |
| <a name="input_repository_names"></a> [repository\_names](#input\_repository\_names) | ECR repository names to create (relative to the account registry), e.g. ['release/api-server-go', 'release/runner-go']. | `list(string)` | `[]` | no |
| <a name="input_scan_on_push"></a> [scan\_on\_push](#input\_scan\_on\_push) | Run the basic image vulnerability scan on push. | `bool` | `true` | no |
| <a name="input_tag_prefix_list"></a> [tag\_prefix\_list](#input\_tag\_prefix\_list) | Only tags starting with one of these count toward max\_image\_count. | `list(string)` | <pre>[<br/>  "v",<br/>  "release",<br/>  "main"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_untagged_image_days"></a> [untagged\_image\_days](#input\_untagged\_image\_days) | Expire untagged images older than this many days. | `number` | `14` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_registry_url"></a> [registry\_url](#output\_registry\_url) | Account-level ECR registry endpoint. Maps to the cross-cloud output contract 'registry'. |
| <a name="output_repository_arns"></a> [repository\_arns](#output\_repository\_arns) | Map of repository name -> ARN. |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Map of repository name -> full repository URL. |
<!-- END_TF_DOCS -->
