# Autoheal BYOC — AWS runner ASG

EC2 Auto Scaling Group runner — the EKS analogue of the AKS VMSS runner. Each
instance runs the runner-go worker as a container (Docker-out-of-Docker: it drives
the host Docker daemon via the mounted socket to launch sandbox containers) and
polls Temporal on the `runners` namespace via the internal NLB.

This is a **separate unit** from the main `aws-byoc` composition on purpose: it
needs `temporal_host` (the internal NLB endpoint), which only exists after the
cluster and Temporal are deployed. Apply it after the app install, feeding forward
the discovered endpoint — mirroring `modules/azure/runner-vmss`.

Identity is an instance profile granted `AmazonEC2ContainerRegistryReadOnly` (pulls
via the `amazon-ecr-credential-helper`, no static registry creds) and
`AmazonSSMManagedInstanceCore` (break-glass via SSM Session Manager, no SSH key or
inbound port). It does not read Secrets Manager — in-cluster apps do, via IRSA.

The Azure analogue is `modules/azure/runner-vmss`. Naming and tags follow the
repo's null-label convention (see `label.tf` and
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
| [aws_autoscaling_group.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_iam_instance_profile.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ecr_pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_parameter.al2023_arm64](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI to launch. Empty resolves the latest Amazon Linux 2023 arm64 AMI via SSM (match the instance\_type architecture). | `string` | `""` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_ecr_registry"></a> [ecr\_registry](#input\_ecr\_registry) | ECR registry endpoint for the credential helper (modules/aws/ecr output registry\_url), e.g. <account>.dkr.ecr.<region>.amazonaws.com. | `string` | n/a | yes |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Desired ASG size. Each runner is an independent Temporal worker; scale out by raising this. | `number` | `1` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Instance type. Default is Graviton (arm64); change ami\_id too if you switch to x86. | `string` | `"m7g.xlarge"` | no |
| <a name="input_key_name"></a> [key\_name](#input\_key\_name) | Optional EC2 key pair for break-glass SSH. Empty (default) relies on SSM Session Manager; no inbound port is opened either way. | `string` | `""` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_max_concurrent_activities"></a> [max\_concurrent\_activities](#input\_max\_concurrent\_activities) | API\_WORKER\_MAX\_CONCURRENT\_ACTIVITIES per runner. | `number` | `5` | no |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | Maximum ASG size. | `number` | `3` | no |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | Minimum ASG size. | `number` | `1` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_root_volume_size_gb"></a> [root\_volume\_size\_gb](#input\_root\_volume\_size\_gb) | Root EBS volume size. Holds Docker layers + sandbox dirs + git datasource caches; 30GB proved insufficient, so default large. | `number` | `200` | no |
| <a name="input_runner_image"></a> [runner\_image](#input\_runner\_image) | Fully-qualified runner-go image, e.g. <registry>/release/runner-go:<ver>. | `string` | n/a | yes |
| <a name="input_runner_name"></a> [runner\_name](#input\_runner\_name) | NAME env the worker registers under. | `string` | `"runner-byoc-eks"` | no |
| <a name="input_sandbox_image"></a> [sandbox\_image](#input\_sandbox\_image) | Fully-qualified sandbox image pre-pulled on boot, e.g. <registry>/dev/sandbox:latest. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnet IDs the ASG launches into. Egress is via the subnets' NAT gateways; instances get no public IP. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_temporal_host"></a> [temporal\_host](#input\_temporal\_host) | Temporal frontend as host:port, the internal NLB (e.g. temporal.internal:7233). The runner polls the `runners` namespace here. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the runner security group lives in (modules/aws/vpc output vpc\_id). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_asg_name"></a> [asg\_name](#output\_asg\_name) | Name of the runner Auto Scaling Group. |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | ID of the runner launch template. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | IAM role ARN of the runner instance profile (granted ECR pull + SSM). |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID attached to the runner instances. |
<!-- END_TF_DOCS -->
