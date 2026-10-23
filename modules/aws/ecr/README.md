# Autoheal BYOC - AWS ECR pull through cache

Private mirror of the public Autoheal registry through an ECR pull through
cache rule. Nothing is pushed: the first pull of an image under
`<registry_host>/<repository_prefix>/` makes ECR create the repository, copy the
image from `upstream_registry_url`, and check upstream again at most once a day.
A repository creation template for the same prefix gives those repositories
encryption (the KMS key when set), tag mutability, a lifecycle policy that
expires untagged images, and the module tags. ECR creates them with a role this
module owns, limited to repositories under the prefix.

`image_registry` is the chart's `global.imageRegistry`. `pull_policy_json` is
the IAM policy a puller needs (the nodes): it includes
`ecr:BatchImportUpstreamImage` and `ecr:CreateRepository`, which the first pull
of each image uses. That first pull needs a route from ECR to the upstream
registry. The Azure analogue is `modules/azure/acr`. Naming and tags follow the
repo's null-label convention (see `label.tf` and
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
| [aws_ecr_pull_through_cache_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_pull_through_cache_rule) | resource |
| [aws_ecr_repository_creation_template.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_creation_template) | resource |
| [aws_iam_role.creation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.creation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
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
| <a name="input_image_tag_mutability"></a> [image\_tag\_mutability](#input\_image\_tag\_mutability) | Tag mutability of the cached repositories. With IMMUTABLE, ECR does not update a cached tag when upstream moves it, which suits the pinned chart-<version> tags. Use MUTABLE to follow moving tags. | `string` | `"IMMUTABLE"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for the cached repositories. Empty uses AES256 (ECR managed keys). The key policy must let IAM policies in the account grant use of the key (modules/aws/kms always does). | `string` | `""` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_repository_prefix"></a> [repository\_prefix](#input\_repository\_prefix) | ECR repository prefix for the pull through cache rule, e.g. autoheal. Images are pulled as <registry\_host>/<repository\_prefix>/<upstream path>. 2 to 30 characters, lowercase. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_untagged_expiry_days"></a> [untagged\_expiry\_days](#input\_untagged\_expiry\_days) | Days after which untagged images in the cached repositories expire. Images referenced by a tagged multi-architecture index are not expired while the index exists. | `number` | `14` | no |
| <a name="input_upstream_namespace"></a> [upstream\_namespace](#input\_upstream\_namespace) | Path under the upstream registry that holds the chart images (app/<name> and external/<name>). It becomes part of image\_registry. Empty when the images sit at the registry root. | `string` | `"e4h3h0d9"` | no |
| <a name="input_upstream_registry_url"></a> [upstream\_registry\_url](#input\_upstream\_registry\_url) | Registry host the cache pulls from, without a scheme. The default is ECR Public, which needs no credentials. | `string` | `"public.ecr.aws"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_creation_role_arn"></a> [creation\_role\_arn](#output\_creation\_role\_arn) | ARN of the IAM role ECR uses to create the cached repositories. |
| <a name="output_image_registry"></a> [image\_registry](#output\_image\_registry) | Registry path the chart pulls app/<name> and external/<name> under (global.imageRegistry): <registry\_host>/<repository\_prefix>/<upstream\_namespace>. |
| <a name="output_pull_policy_json"></a> [pull\_policy\_json](#output\_pull\_policy\_json) | IAM policy JSON that lets a role pull through the cache: ecr:GetAuthorizationToken on *, and the pull, import and create actions on the prefix's repositories. |
| <a name="output_registry_host"></a> [registry\_host](#output\_registry\_host) | Private registry host for this account and region, <account>.dkr.ecr.<region>.amazonaws.com. |
| <a name="output_repository_arn_pattern"></a> [repository\_arn\_pattern](#output\_repository\_arn\_pattern) | ARN pattern that matches every repository the rule creates, for IAM policies. |
| <a name="output_repository_prefix"></a> [repository\_prefix](#output\_repository\_prefix) | Repository prefix of the pull through cache rule. |
<!-- END_TF_DOCS -->
