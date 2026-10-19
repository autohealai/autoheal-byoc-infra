# Autoheal BYOC - AWS EKS Pod Identity role

One IAM role for EKS Pod Identity plus the associations that bind it to
Kubernetes service accounts. Replaces the 1.x IRSA module: no IAM OIDC provider
and no service account annotations. The cluster needs the
`eks-pod-identity-agent` add-on (on by default in `modules/aws/eks`).

The trust policy allows `sts:AssumeRole` and `sts:TagSession` for the
`pods.eks.amazonaws.com` service only when `aws:SourceAccount` is this account
and `aws:SourceArn` is the cluster named in `cluster_name`. The role keeps
working if the cluster is rebuilt with the same name.

Permissions:

- `inline_policies`: policy JSON documents keyed by policy name, one
  `aws_iam_role_policy` each.
- `managed_policy_arns`: managed policy ARNs keyed by a fixed name, one
  attachment each.

Keys must be known at plan time; the documents and ARNs may come from the same
apply. Associations are keyed by `<namespace>/<service_account>`. Set
`association_enabled = false` to create only the role when the deployer cannot
create associations.

The Azure analogue is workload identity with a user-assigned managed identity.
Naming and tags follow the repo's null-label convention (see `label.tf` and
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
| [aws_eks_pod_identity_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_association_enabled"></a> [association\_enabled](#input\_association\_enabled) | Create the Pod Identity associations. Set false to create only the role, when the deployer cannot call eks:CreatePodIdentityAssociation and someone else creates them. | `bool` | `true` | no |
| <a name="input_associations"></a> [associations](#input\_associations) | Kubernetes service accounts that get this role, e.g. [{ namespace = "autoheal", service\_account = "api-server" }]. Each pair becomes one Pod Identity association. Names must be known at plan time. | <pre>list(object({<br/>    namespace       = string<br/>    service_account = string<br/>  }))</pre> | `[]` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster the role is for. The trust policy only accepts Pod Identity requests from this cluster, and the associations are created in it. | `string` | n/a | yes |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_inline_policies"></a> [inline\_policies](#input\_inline\_policies) | Inline IAM policy JSON documents for the role, keyed by policy name (e.g. { storage = data.aws\_iam\_policy\_document.s3.json }). Keys must be known at plan time; the documents may come from the same apply. | `map(string)` | `{}` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_managed_policy_arns"></a> [managed\_policy\_arns](#input\_managed\_policy\_arns) | Managed IAM policy ARNs to attach to the role, keyed by a fixed name (e.g. { bedrock = aws\_iam\_policy.bedrock.arn }). Keys must be known at plan time; the ARNs may come from the same apply. | `map(string)` | `{}` | no |
| <a name="input_max_session_duration"></a> [max\_session\_duration](#input\_max\_session\_duration) | Maximum session length in seconds for the role (3600-43200). The Pod Identity agent refreshes credentials before they expire. | `number` | `3600` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of a managed policy to set as the role's permissions boundary. Empty sets none. | `string` | `""` | no |
| <a name="input_role_path"></a> [role\_path](#input\_role\_path) | IAM path for the role. Must start and end with '/'. | `string` | `"/"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_association_arns"></a> [association\_arns](#output\_association\_arns) | Pod Identity association ARNs keyed by "<namespace>/<service\_account>". Empty when association\_enabled is false. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IAM role. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the IAM role, for attaching more policies outside the module. |
<!-- END_TF_DOCS -->
