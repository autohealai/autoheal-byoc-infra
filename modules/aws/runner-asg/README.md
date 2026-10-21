# Autoheal BYOC - AWS runner ASG

EC2 Auto Scaling group that runs the runner-go worker as a container
(Docker-out-of-Docker) in private subnets, polling Temporal's `runners`
namespace at `temporal_host`. It is the AWS port of `modules/azure/runner-vmss`:
the same cloud-init files, environment and systemd unit, on Amazon Linux 2023
with Docker from its package repository. No public address: egress goes through
the subnets' NAT gateway.

The composition creates it in the same apply as the cluster: `temporal_host`
and `tool_response_callback_url` point at the internal NLB, and the runner
retries until Temporal answers. Before each start the systemd unit pulls
`runner_image` and retries with a backoff (15 seconds, doubling up to 5
minutes) until the pull succeeds. When `ecr_registry_host` is set, the
instances install the ECR credential helper so docker pulls with the instance
role, and a timer writes a login file every hour for runner-go, which pulls the
sandbox image through the Docker API and does not use credential helpers. Pull
access comes from `additional_iam_policy_arns`.

The launch template requires IMDSv2 with a hop limit of 1, so containers,
including untrusted sandboxes, cannot reach the instance role. Host names are
the instance ID, which runner-go uses for its per-host task queue. There is no
SSH key and no ingress rule: access is through SSM Session Manager. The root
volume is encrypted gp3. A change to the launch template, such as a new runner
image or AMI, rolls the instances through an instance refresh. Naming and tags
follow the repo's null-label convention (see `label.tf` and
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
| [aws_autoscaling_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_iam_instance_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_ami.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_ec2_instance_type.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_instance_type) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_ssm_parameter.al2023](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_iam_policy_arns"></a> [additional\_iam\_policy\_arns](#input\_additional\_iam\_policy\_arns) | More IAM policies for the instance role, keyed by a stable name, e.g. { ecr-pull = <policy ARN> }. The keys must be known at plan time; the ARNs may be created in the same apply. | `map(string)` | `{}` | no |
| <a name="input_additional_security_group_ids"></a> [additional\_security\_group\_ids](#input\_additional\_security\_group\_ids) | More security groups for the instances, next to the module's own egress-only group. | `list(string)` | `[]` | no |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI ID. Empty uses the latest Amazon Linux 2023 AMI from the public SSM parameter for the architecture, so an apply after AWS publishes a new AMI rolls the instances. Pin an ID to control when that happens. cloud-init expects Amazon Linux 2023 (dnf packages docker and amazon-ecr-credential-helper). | `string` | `""` | no |
| <a name="input_architecture"></a> [architecture](#input\_architecture) | CPU architecture of the AMI and instance type: x86\_64 or arm64. The runner and sandbox images must be built for it. | `string` | `"x86_64"` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_ecr_registry_host"></a> [ecr\_registry\_host](#input\_ecr\_registry\_host) | ECR registry host the images come from, e.g. 123456789012.dkr.ecr.us-west-2.amazonaws.com (the ecr module's registry\_host). When set, the instances install amazon-ecr-credential-helper, the host docker CLI pulls from it with the instance role, and runner-go gets a login file refreshed every hour. The role needs pull access: pass the ecr module's pull policy through additional\_iam\_policy\_arns. Empty means the images are public and no login runs. | `string` | `""` | no |
| <a name="input_egress_cidr_blocks"></a> [egress\_cidr\_blocks](#input\_egress\_cidr\_blocks) | IPv4 CIDRs the instances may reach on any port. Sandboxes need the internet (git hosts, package registries, customer APIs), and the runner needs Temporal, the registry and SSM. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of runner instances (min = max = desired). Each runner is an independent Temporal worker; scale out by raising this. 0 stops all runners. | `number` | `1` | no |
| <a name="input_instance_refresh_max_healthy_percentage"></a> [instance\_refresh\_max\_healthy\_percentage](#input\_instance\_refresh\_max\_healthy\_percentage) | Upper limit of instances in service during an instance refresh, as a share of instance\_count (100 to 200). Above 100 the group launches replacements before it terminates the old instances. | `number` | `100` | no |
| <a name="input_instance_refresh_min_healthy_percentage"></a> [instance\_refresh\_min\_healthy\_percentage](#input\_instance\_refresh\_min\_healthy\_percentage) | Share of instance\_count that stays in service during an instance refresh. With one instance, anything below 100 stops it before its replacement starts; set 100 with instance\_refresh\_max\_healthy\_percentage above 100 to start the replacement first. | `number` | `50` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type. Must support var.architecture. m7i.xlarge (4 vCPU, 16 GiB) matches the size of Autoheal's hosted runners. | `string` | `"m7i.xlarge"` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_max_concurrent_activities"></a> [max\_concurrent\_activities](#input\_max\_concurrent\_activities) | API\_WORKER\_MAX\_CONCURRENT\_ACTIVITIES per runner. 20 matches Autoheal's hosted runners on the same 4 vCPU, 16 GiB size. | `number` | `20` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | Permissions boundary policy ARN for the instance role. Empty sets none. | `string` | `""` | no |
| <a name="input_root_volume_iops"></a> [root\_volume\_iops](#input\_root\_volume\_iops) | gp3 IOPS of the root volume. 3000 is the gp3 baseline and matches Autoheal's hosted runners. | `number` | `3000` | no |
| <a name="input_root_volume_kms_key_arn"></a> [root\_volume\_kms\_key\_arn](#input\_root\_volume\_kms\_key\_arn) | KMS key ARN for the root volume. Empty uses the account's default EBS key. A customer managed key must allow the Auto Scaling service-linked role (AWSServiceRoleForAutoScaling) to use it, or instances fail to launch. The ARN may be created in the same apply. | `string` | `""` | no |
| <a name="input_root_volume_size_gb"></a> [root\_volume\_size\_gb](#input\_root\_volume\_size\_gb) | Root volume size in GiB. Holds Docker layers, sandbox dirs and git datasource caches. | `number` | `200` | no |
| <a name="input_root_volume_throughput"></a> [root\_volume\_throughput](#input\_root\_volume\_throughput) | gp3 throughput of the root volume in MiB/s. 125 is the gp3 baseline. | `number` | `125` | no |
| <a name="input_runner_image"></a> [runner\_image](#input\_runner\_image) | Fully qualified runner-go image, e.g. public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0. | `string` | n/a | yes |
| <a name="input_runner_name"></a> [runner\_name](#input\_runner\_name) | NAME env the worker registers under, e.g. runner-byoc-eks. | `string` | n/a | yes |
| <a name="input_sandbox_image"></a> [sandbox\_image](#input\_sandbox\_image) | Fully qualified sandbox image to pre-pull on boot. Empty skips the pre-pull. | `string` | `""` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnets the instances launch in, ideally one per Availability Zone. Egress goes through the subnets' NAT gateway; the instances get no public address. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_temporal_host"></a> [temporal\_host](#input\_temporal\_host) | Temporal frontend host:port the runner polls, e.g. the internal NLB: internal-acme-play-autoheal-0123456789.elb.us-west-2.amazonaws.com:7233. May be created in the same apply. | `string` | n/a | yes |
| <a name="input_tool_response_callback_url"></a> [tool\_response\_callback\_url](#input\_tool\_response\_callback\_url) | URL the runner posts sandbox tool results to, set as SANDBOX\_TOOL\_RESPONSE\_CALLBACK\_URL: the api-server-go internal listener, e.g. http://<internal NLB>:8083/api/v1/internal/sandbox-tool-responses. Empty leaves it unset and tool results go through Temporal only. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the runner security group lives in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the runner Auto Scaling group. |
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the runner instance role. |
| <a name="output_iam_role_name"></a> [iam\_role\_name](#output\_iam\_role\_name) | Name of the runner instance role, for attaching more policies outside the module. |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | ID of the runner launch template. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the runner security group, e.g. for the NLB's allowed\_security\_group\_ids. |
<!-- END_TF_DOCS -->
