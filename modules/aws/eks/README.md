# Autoheal BYOC - AWS EKS

EKS cluster, one managed node group and the EKS managed add-ons for a
BYOC-on-EKS Autoheal install.

- **Access**: EKS access entries only (`authentication_mode = "API"`). The
  creator gets cluster admin when `bootstrap_cluster_creator_admin_permissions`
  is true; everyone else goes in `access_entries`. EKS adds the node role entry
  itself. There is no aws-auth ConfigMap.
- **Workload credentials**: EKS Pod Identity (`modules/aws/pod-identity`). The
  module creates no IAM OIDC provider; `oidc_issuer_url` is output for anyone
  who needs it.
- **Encryption**: Kubernetes Secrets use envelope encryption with
  `secrets_kms_key_arn`. Node volumes are encrypted gp3, with the account
  default EBS key unless `node_disk_kms_key_arn` is set.
- **Logs**: all five control plane log types go to `/aws/eks/<name>/cluster`,
  which the module creates first with `log_retention_days` and optional
  `log_kms_key_arn`.
- **Endpoint**: private endpoint always on. The public endpoint is on by
  default so an operator outside the VPC can install; narrow
  `public_access_cidrs` or set `endpoint_public_access = false`.
- **Nodes**: one managed node group on a module-owned launch template with
  IMDSv2 required and a hop limit of 1, so pods cannot read the node role.
  Nodes use the EKS cluster security group. Node auto repair is on. The node
  group follows the control plane version, and a replacement brings the new
  group up before the old one drains.
- **Add-ons**: `vpc-cni` (network policy on) and `eks-pod-identity-agent` go on
  before the node group, the rest after it. A null version picks the default
  version for the Kubernetes version. When `aws-ebs-csi-driver` is in `addons`
  the module creates its Pod Identity role.
- **Deletion protection** is on by default. To destroy, apply with
  `deletion_protection = false` first.

## Notes

- A customer managed key in `node_disk_kms_key_arn` must let the
  `AWSServiceRoleForAutoScaling` service-linked role use it and create grants,
  or nodes fail to launch. The account default EBS key needs nothing.
- If a StorageClass sets `kmsKeyId`, pass that key in `ebs_csi_kms_key_arns`.
- Changing `bootstrap_cluster_creator_admin_permissions`, `service_ipv4_cidr` or
  `secrets_kms_key_arn` after creation replaces or fails the cluster.

The Azure analogue is `modules/azure/aks`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration wired to the
`kms` and `vpc` modules.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.9 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | ../../_shared/label | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eks_access_entry.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_eks_addon.after_nodes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.before_nodes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_node_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cluster_secrets_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ebs_csi_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eks_addon_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_addon_version) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_entries"></a> [access\_entries](#input\_access\_entries) | Extra principals that get Kubernetes API access, keyed by a fixed name (e.g. "platform-admins"). Each gets one access policy, cluster wide or limited to namespaces. | <pre>map(object({<br/>    principal_arn     = string<br/>    policy_arn        = optional(string, "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy")<br/>    access_scope_type = optional(string, "cluster")<br/>    namespaces        = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_addons"></a> [addons](#input\_addons) | EKS managed add-ons keyed by add-on name. version null uses the default version for kubernetes\_version. configuration\_values is the add-on's JSON config (see aws eks describe-addon-configuration). vpc-cni and eks-pod-identity-agent are installed before the node group, the rest after. | <pre>map(object({<br/>    version              = optional(string)<br/>    configuration_values = optional(string)<br/>  }))</pre> | <pre>{<br/>  "aws-ebs-csi-driver": {},<br/>  "aws-secrets-store-csi-driver-provider": {},<br/>  "coredns": {},<br/>  "eks-pod-identity-agent": {},<br/>  "kube-proxy": {},<br/>  "vpc-cni": {<br/>    "configuration_values": "{\"enableNetworkPolicy\":\"true\"}"<br/>  }<br/>}</pre> | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_bootstrap_cluster_creator_admin_permissions"></a> [bootstrap\_cluster\_creator\_admin\_permissions](#input\_bootstrap\_cluster\_creator\_admin\_permissions) | Give the IAM principal that creates the cluster a cluster-admin access entry. Changing it after creation replaces the cluster. Do not also list that principal in access\_entries. | `bool` | `true` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Block cluster deletion. To destroy the cluster, apply with false first. | `bool` | `true` | no |
| <a name="input_ebs_csi_kms_key_arns"></a> [ebs\_csi\_kms\_key\_arns](#input\_ebs\_csi\_kms\_key\_arns) | KMS key ARNs the EBS CSI driver may use for volumes it creates. Needed only when a StorageClass sets kmsKeyId or the account default EBS key is a customer managed key. | `list(string)` | `[]` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_enabled_log_types"></a> [enabled\_log\_types](#input\_enabled\_log\_types) | Control plane log types sent to CloudWatch Logs. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Expose the Kubernetes API on a public endpoint (limited by public\_access\_cidrs). The private endpoint is always on. Set false once the operator reaches the API from inside the VPC. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes minor version, e.g. 1.36. Raising it upgrades the control plane, then the node group and the add-ons that use the default version. EKS upgrades one minor version at a time and never downgrades. | `string` | `"1.36"` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_log_kms_key_arn"></a> [log\_kms\_key\_arn](#input\_log\_kms\_key\_arn) | KMS key ARN to encrypt the control plane log group. The key policy must let the CloudWatch Logs service use it (modules/aws/kms cloudwatch\_logs\_enabled = true). Empty uses CloudWatch Logs default encryption. | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention of the control plane log group in days. Must be a value CloudWatch Logs accepts; 0 keeps logs forever. | `number` | `365` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_node_additional_policy_arns"></a> [node\_additional\_policy\_arns](#input\_node\_additional\_policy\_arns) | Extra IAM policy ARNs attached to the node role, keyed by a fixed name (e.g. { ecr\_pull\_through = aws\_iam\_policy.x.arn }). Keys must be known at plan time; the ARNs may come from the same apply. | `map(string)` | `{}` | no |
| <a name="input_node_ami_type"></a> [node\_ami\_type](#input\_node\_ami\_type) | EKS optimized AMI type, e.g. AL2023\_x86\_64\_STANDARD or AL2023\_ARM\_64\_STANDARD (match node\_instance\_types). Amazon Linux 2023 and Bottlerocket types are accepted. Changing it replaces the node group. | `string` | `"AL2023_x86_64_STANDARD"` | no |
| <a name="input_node_capacity_type"></a> [node\_capacity\_type](#input\_node\_capacity\_type) | ON\_DEMAND or SPOT. Changing it replaces the node group. | `string` | `"ON_DEMAND"` | no |
| <a name="input_node_desired_size"></a> [node\_desired\_size](#input\_node\_desired\_size) | Number of nodes. Terraform owns this value; there is no cluster autoscaler. | `number` | `3` | no |
| <a name="input_node_disk_kms_key_arn"></a> [node\_disk\_kms\_key\_arn](#input\_node\_disk\_kms\_key\_arn) | KMS key ARN for node volumes. Empty uses the account's default EBS key. A customer managed key must let the AWSServiceRoleForAutoScaling service-linked role use it and create grants, or nodes fail to launch. | `string` | `""` | no |
| <a name="input_node_disk_size_gb"></a> [node\_disk\_size\_gb](#input\_node\_disk\_size\_gb) | Size of each node's data volume in GiB (gp3, encrypted). It holds container images and emptyDir volumes. | `number` | `100` | no |
| <a name="input_node_instance_types"></a> [node\_instance\_types](#input\_node\_instance\_types) | EC2 instance types for the node group. More than one only helps with SPOT capacity. | `list(string)` | <pre>[<br/>  "m7i.xlarge"<br/>]</pre> | no |
| <a name="input_node_labels"></a> [node\_labels](#input\_node\_labels) | Kubernetes labels added to every node. | `map(string)` | `{}` | no |
| <a name="input_node_max_size"></a> [node\_max\_size](#input\_node\_max\_size) | Maximum number of nodes. Also bounds the extra nodes EKS adds during a rolling update. | `number` | `6` | no |
| <a name="input_node_max_unavailable_percentage"></a> [node\_max\_unavailable\_percentage](#input\_node\_max\_unavailable\_percentage) | Largest share of nodes, in percent, that may be unavailable during a node group update (1-100). | `number` | `33` | no |
| <a name="input_node_min_size"></a> [node\_min\_size](#input\_node\_min\_size) | Minimum number of nodes. | `number` | `3` | no |
| <a name="input_node_repair_enabled"></a> [node\_repair\_enabled](#input\_node\_repair\_enabled) | Let EKS replace nodes that report unhealthy (node auto repair). | `bool` | `true` | no |
| <a name="input_public_access_cidrs"></a> [public\_access\_cidrs](#input\_public\_access\_cidrs) | CIDRs allowed to reach the public API endpoint. Narrow this to the operator and CI egress ranges. Ignored when endpoint\_public\_access is false. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | ARN of the symmetric KMS key (same region) used for envelope encryption of Kubernetes Secrets. Cannot be changed after the cluster is created. | `string` | n/a | yes |
| <a name="input_service_ipv4_cidr"></a> [service\_ipv4\_cidr](#input\_service\_ipv4\_cidr) | CIDR for Kubernetes service IPs. Empty lets EKS pick 10.100.0.0/16 or 172.20.0.0/16. Set it when those overlap a network the cluster must reach. Cannot be changed after creation. | `string` | `""` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnet IDs for the control plane network interfaces and the nodes, in at least two availability zones (modules/aws/vpc private\_subnet\_ids). | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_upgrade_support_type"></a> [upgrade\_support\_type](#input\_upgrade\_support\_type) | STANDARD: EKS upgrades the control plane automatically when standard support ends. EXTENDED: the version stays on paid extended support. | `string` | `"STANDARD"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC that holds subnet\_ids. EKS derives the VPC from the subnets; this is checked against it after the cluster is created. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudWatch log group that receives control plane logs. |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the EKS cluster. |
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64 encoded cluster CA certificate, as AWS returns it. Public, not a secret. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | HTTPS endpoint of the Kubernetes API server. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_cluster_role_arn"></a> [cluster\_role\_arn](#output\_cluster\_role\_arn) | ARN of the IAM role the control plane uses. |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | ID of the security group EKS created for the cluster. The control plane and all nodes use it; allow it on data stores the pods reach. |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | Kubernetes version of the control plane. |
| <a name="output_ebs_csi_driver_role_arn"></a> [ebs\_csi\_driver\_role\_arn](#output\_ebs\_csi\_driver\_role\_arn) | ARN of the IAM role the EBS CSI driver uses through Pod Identity. Empty when aws-ebs-csi-driver is not in addons. |
| <a name="output_node_group_name"></a> [node\_group\_name](#output\_node\_group\_name) | Name of the managed node group. |
| <a name="output_node_role_arn"></a> [node\_role\_arn](#output\_node\_role\_arn) | ARN of the node IAM role. |
| <a name="output_node_role_name"></a> [node\_role\_name](#output\_node\_role\_name) | Name of the node IAM role, for attaching more policies outside the module. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | OIDC issuer URL of the cluster. Not used for workload credentials here (Pod Identity is), but useful for external identity federation. |
<!-- END_TF_DOCS -->
