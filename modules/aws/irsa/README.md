# Autoheal BYOC — AWS IRSA (app identity)

IAM Role for Service Accounts (IRSA) for the Autoheal app. Trusts the EKS cluster
OIDC provider for the given Kubernetes service accounts and grants the app read
access to its Secrets Manager prefix and S3 bucket(s). Annotate the app service
account with `eks.amazonaws.com/role-arn = <role_arn>` and it assumes this role
with no static credentials.

The role ARN is the cross-cloud `runner_identity`. The Azure analogue is
`modules/azure/workload-identity` (UAMI + federated credential). Naming and tags
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
| [aws_iam_policy.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_extra_policy_arns"></a> [extra\_policy\_arns](#input\_extra\_policy\_arns) | Additional managed/customer policy ARNs to attach to the role. | `list(string)` | `[]` | no |
| <a name="input_federated_service_accounts"></a> [federated\_service\_accounts](#input\_federated\_service\_accounts) | Kubernetes service accounts allowed to assume this role (trust subject system:serviceaccount:<namespace>:<service\_account>). | <pre>list(object({<br/>    namespace       = string<br/>    service_account = string<br/>  }))</pre> | n/a | yes |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the EKS cluster OIDC provider (modules/aws/eks output oidc\_provider\_arn). | `string` | n/a | yes |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | URL of the EKS cluster OIDC issuer (modules/aws/eks output oidc\_provider\_url), e.g. https://oidc.eks.<region>.amazonaws.com/id/XXXX. | `string` | n/a | yes |
| <a name="input_role_name_override"></a> [role\_name\_override](#input\_role\_name\_override) | Force an exact IAM role name. Empty derives '<label id>-irsa'. | `string` | `""` | no |
| <a name="input_s3_bucket_arns"></a> [s3\_bucket\_arns](#input\_s3\_bucket\_arns) | S3 bucket ARNs the app may read/write (object access is granted on '<arn>/*'). Empty skips the S3 statements. | `list(string)` | `[]` | no |
| <a name="input_secret_arns"></a> [secret\_arns](#input\_secret\_arns) | Secret ARNs (or wildcards like '<prefix>/*') the app may read. Empty skips the secrets statement. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | IAM role ARN to annotate on the app service account (eks.amazonaws.com/role-arn). Maps to the cross-cloud output contract 'runner\_identity'. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | IAM role name. |
<!-- END_TF_DOCS -->
