# Autoheal BYOC - AWS runner ASG

EC2 Auto Scaling group that runs the runner-go worker as a container
(Docker-out-of-Docker) in private subnets, polling Temporal's `runners`
namespace at `temporal_host`. It is the AWS port of `modules/azure/runner-vmss`:
the same cloud-init files, environment and systemd unit, on Amazon Linux 2023
(or an image built from it) with Docker from its package repository. No
public address: the subnets' routes give the way out, and `http_proxy` covers
subnets whose way out is a proxy. `trusted_ca_certificates` go into the host's
trust store, for a registry or proxy with a private CA. `custom_ca_certificate`
is written to `/opt/runner-go/ca/custom-ca.pem` and mounted into runner-go,
which trusts those private root CAs and adds them to every sandbox it
creates.

`compositions/aws-runner` creates it as its own step, after the app:
`temporal_host` is the internal runner load balancer of `compositions/aws` on
7233, and `tool_response_callback_url` api-server-go's internal listener on the
same load balancer. The runner connects as Autoheal's hosted runners do:
plain gRPC and HTTP, with no TLS and no key in the user data or anywhere
else, so the load balancer's security group alone decides who connects. The
runner-go unit pulls `runner_image`, retrying with a backoff (15 seconds,
doubling up to 5 minutes) until it succeeds. When `ecr_registry_host` is set,
the role may pull from it (limited to `ecr_repository_prefix` when set), the
instances install the ECR credential helper so docker pulls with the
instance role, and a timer writes a login file every hour for runner-go,
which pulls the sandbox image through the Docker API and does not use
credential helpers.

For tool results through the edge, `tool_response_callback_url` is the app
host on 443 and `tool_response_token_secret_arn` the secret that holds the
callback key. The role may read that one secret, and decrypt with
`tool_response_token_kms_key_arn` only through Secrets Manager. Before each
runner start a script reads the key with the AWS CLI and writes it to a
root-only file that runner-go gets as `SANDBOX_TOOL_RESPONSE_CALLBACK_TOKEN`, so
the key is never in the user data, and a changed key reaches the runner on its
next restart. Without the key the runner does not start.

The launch template requires IMDSv2 with a hop limit of 1. runner-go runs on
a Docker network of its own and starts sandboxes on Docker's default bridge.
A firewall script in Docker's `DOCKER-USER` chain rejects container traffic to
the metadata address, so containers cannot reach the instance role, and
sandbox traffic to the runner load balancer and to
`sandbox_blocked_destinations`, so sandboxes, which run untrusted code, cannot
reach Temporal. It runs before each runner start and every 5 minutes, and
looks the names up again each time. Host names are the instance ID, which
runner-go uses for its per-host task queue. Access is through SSM Session
Manager (`ssm_enabled`), or SSH with `key_name` and `ssh_ingress_cidr_blocks`.
The root volume is encrypted gp3. A change to the launch template, such as a
new runner image or AMI, rolls the instances through an instance refresh. The
cloud-init is gzipped into the user data to stay inside the 16 KB EC2 limit;
Terraform's gzip output is stable, so an unchanged cloud-init rolls nothing.

Where a central team owns IAM or the network, `existing_instance_profile_arn`
and `existing_security_group_id` replace the module's role and security group,
and `required_role_policies` lists the trust policy, inline policies and
managed policies the brought role needs. `ami_name_filter` with `ami_owners`
picks a company image instead of the public Amazon Linux 2023 AMI. Naming and
tags follow the repo's null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration, and
[compositions/aws-runner](../../../compositions/aws-runner) for the composition
that wires it to `compositions/aws`.

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
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_ami.by_name](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_ami.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_ec2_instance_type.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_instance_type) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_ssm_parameter.al2023](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_iam_policy_arns"></a> [additional\_iam\_policy\_arns](#input\_additional\_iam\_policy\_arns) | More IAM policies for the instance role, keyed by a stable name, e.g. { ecr-pull = <policy ARN> }. The keys must be known at plan time; the ARNs may be created in the same apply. | `map(string)` | `{}` | no |
| <a name="input_additional_inline_policies"></a> [additional\_inline\_policies](#input\_additional\_inline\_policies) | More inline policies for the instance role, name => policy JSON, e.g. { logs = <JSON> }. The names must be known at plan time. With existing\_instance\_profile\_arn they are listed in required\_role\_policies instead. | `map(string)` | `{}` | no |
| <a name="input_additional_security_group_ids"></a> [additional\_security\_group\_ids](#input\_additional\_security\_group\_ids) | More security groups for the instances, next to the module's group or existing\_security\_group\_id. | `list(string)` | `[]` | no |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI ID to pin. Empty picks one with ami\_name\_filter, or the latest Amazon Linux 2023 AMI from the public SSM parameter for the architecture when that is empty too. cloud-init expects Amazon Linux 2023 or an image built from it (dnf, the docker package). | `string` | `""` | no |
| <a name="input_ami_name_filter"></a> [ami\_name\_filter](#input\_ami\_name\_filter) | AMI name pattern (wildcards *), e.g. a company's hardened Amazon Linux 2023 image: *golden-amzn-linux-2023-v*. The newest match from ami\_owners for the architecture is used. Ignored when ami\_id is set. A newer match rolls the instances at the next apply; pin ami\_id to control when. | `string` | `""` | no |
| <a name="input_ami_owners"></a> [ami\_owners](#input\_ami\_owners) | Owners searched with ami\_name\_filter: account IDs or self, amazon, aws-marketplace. Required with ami\_name\_filter. | `list(string)` | `[]` | no |
| <a name="input_architecture"></a> [architecture](#input\_architecture) | CPU architecture of the AMI and instance type: x86\_64 or arm64. The runner and sandbox images must be built for it. | `string` | `"x86_64"` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_custom_ca_certificate"></a> [custom\_ca\_certificate](#input\_custom\_ca\_certificate) | PEM of private root CAs, one after another, that runner-go and every sandbox it creates trust on top of the public CAs: the same PEM as the vault entry of the chart's global.trust.caVaultEntry. Written to /opt/runner-go/ca/custom-ca.pem, the path runner-go reads by default. The host's trust store does not get them; that is trusted\_ca\_certificates. Changing it rolls the instances. Empty adds none. | `string` | `""` | no |
| <a name="input_ecr_registry_host"></a> [ecr\_registry\_host](#input\_ecr\_registry\_host) | ECR registry host the images come from, e.g. 123456789012.dkr.ecr.us-west-2.amazonaws.com. When set, the instances install amazon-ecr-credential-helper, the host docker CLI pulls from it with the instance role, runner-go gets a login file refreshed every hour, and the role gets the inline policy ecr-pull on it (pull, and the import and create a pull-through cache needs). Empty means the images are public or come from a registry that needs no login. | `string` | `""` | no |
| <a name="input_ecr_repository_prefix"></a> [ecr\_repository\_prefix](#input\_ecr\_repository\_prefix) | Repository prefix the ecr-pull policy is limited to, such as the repository prefix of a pull-through cache. Empty means every repository in ecr\_registry\_host. Used only with ecr\_registry\_host. | `string` | `""` | no |
| <a name="input_egress_cidr_blocks"></a> [egress\_cidr\_blocks](#input\_egress\_cidr\_blocks) | IPv4 CIDRs the instances may reach on any port, on the module's security group. Sandboxes need the git hosts, package registries and the APIs the tools call, and the runner needs Temporal, the registry and Secrets Manager. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_existing_instance_profile_arn"></a> [existing\_instance\_profile\_arn](#input\_existing\_instance\_profile\_arn) | ARN of an instance profile you already have, for accounts where a central team owns IAM. When set, the module creates no role, policy or profile; ssm\_enabled, additional\_inline\_policies and additional\_iam\_policy\_arns are not attached, and required\_role\_policies lists what the role needs. Empty means the module creates them. | `string` | `""` | no |
| <a name="input_existing_security_group_id"></a> [existing\_security\_group\_id](#input\_existing\_security\_group\_id) | ID of a security group you already have for the instances. When set, the module creates no security group and adds no rule; egress\_cidr\_blocks and ssh\_ingress\_cidr\_blocks are ignored. Its owner allows egress to Temporal, the registry, Secrets Manager and what the sandboxes call. Empty means the module creates the group. | `string` | `""` | no |
| <a name="input_http_proxy"></a> [http\_proxy](#input\_http\_proxy) | Outbound HTTP proxy, e.g. http://proxy.acme.example:8080, for subnets whose way out is a proxy. When set, dnf, the Docker daemon (image pulls), the ECR login and runner-go use it, except for no\_proxy. Sandboxes do not get it. Empty uses none. | `string` | `""` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of runner instances (min = max = desired). Each runner is an independent Temporal worker; scale out by raising this. 0 stops all runners. | `number` | `1` | no |
| <a name="input_instance_refresh_max_healthy_percentage"></a> [instance\_refresh\_max\_healthy\_percentage](#input\_instance\_refresh\_max\_healthy\_percentage) | Upper limit of instances in service during an instance refresh, as a share of instance\_count (100 to 200). Above 100 the group launches replacements before it terminates the old instances. | `number` | `100` | no |
| <a name="input_instance_refresh_min_healthy_percentage"></a> [instance\_refresh\_min\_healthy\_percentage](#input\_instance\_refresh\_min\_healthy\_percentage) | Share of instance\_count that stays in service during an instance refresh. With one instance, anything below 100 stops it before its replacement starts; set 100 with instance\_refresh\_max\_healthy\_percentage above 100 to start the replacement first. | `number` | `50` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type. Must support var.architecture. m7i.xlarge (4 vCPU, 16 GiB) matches the size of Autoheal's hosted runners. | `string` | `"m7i.xlarge"` | no |
| <a name="input_key_name"></a> [key\_name](#input\_key\_name) | EC2 key pair for SSH as ec2-user, for accounts without SSM Session Manager. Pair it with ssh\_ingress\_cidr\_blocks or a security group that allows TCP 22. Empty adds no key. | `string` | `""` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_max_concurrent_activities"></a> [max\_concurrent\_activities](#input\_max\_concurrent\_activities) | API\_WORKER\_MAX\_CONCURRENT\_ACTIVITIES per runner. 20 matches Autoheal's hosted runners on the same 4 vCPU, 16 GiB size. | `number` | `20` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_no_proxy"></a> [no\_proxy](#input\_no\_proxy) | Hosts, domains (.acme.example) and IPv4 CIDRs reached without http\_proxy, such as an internal registry or VPC endpoints. The module always adds localhost, 127.0.0.1, the instance metadata address and the hosts of temporal\_host and tool\_response\_callback\_url, which the runner reaches directly. Used only with http\_proxy. | `list(string)` | `[]` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | Permissions boundary policy ARN for the instance role. Empty sets none. | `string` | `""` | no |
| <a name="input_root_volume_iops"></a> [root\_volume\_iops](#input\_root\_volume\_iops) | gp3 IOPS of the root volume. 3000 is the gp3 baseline and matches Autoheal's hosted runners. | `number` | `3000` | no |
| <a name="input_root_volume_kms_key_arn"></a> [root\_volume\_kms\_key\_arn](#input\_root\_volume\_kms\_key\_arn) | KMS key ARN for the root volume. Empty uses the account's default EBS key. A customer managed key must allow the Auto Scaling service-linked role (AWSServiceRoleForAutoScaling) to use it, or instances fail to launch. The ARN may be created in the same apply. | `string` | `""` | no |
| <a name="input_root_volume_size_gb"></a> [root\_volume\_size\_gb](#input\_root\_volume\_size\_gb) | Root volume size in GiB. Holds Docker layers, sandbox dirs and git datasource caches. | `number` | `200` | no |
| <a name="input_root_volume_throughput"></a> [root\_volume\_throughput](#input\_root\_volume\_throughput) | gp3 throughput of the root volume in MiB/s. 125 is the gp3 baseline. | `number` | `125` | no |
| <a name="input_runner_image"></a> [runner\_image](#input\_runner\_image) | Fully qualified runner-go image, e.g. public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0. | `string` | n/a | yes |
| <a name="input_runner_name"></a> [runner\_name](#input\_runner\_name) | NAME env the worker registers under, e.g. acme-prod-autoheal-runner. | `string` | n/a | yes |
| <a name="input_sandbox_blocked_destinations"></a> [sandbox\_blocked\_destinations](#input\_sandbox\_blocked\_destinations) | More destinations sandboxes may not reach over TCP, on top of the host of temporal\_host and of an http:// tool\_response\_callback\_url, which they never reach: IPv4 addresses, IPv4 CIDRs such as 10.60.0.0/16, or DNS names. Names are looked up when runner-go starts and every 5 minutes after. Sandboxes run untrusted code, and the runner load balancer takes no key, so only the runner itself may use it. An https:// tool\_response\_callback\_url is the edge, which checks the callback key, so sandboxes keep it. | `list(string)` | `[]` | no |
| <a name="input_sandbox_image"></a> [sandbox\_image](#input\_sandbox\_image) | Fully qualified sandbox image to pre-pull on boot. Empty skips the pre-pull. | `string` | `""` | no |
| <a name="input_ssh_ingress_cidr_blocks"></a> [ssh\_ingress\_cidr\_blocks](#input\_ssh\_ingress\_cidr\_blocks) | IPv4 CIDRs that may reach the instances on TCP 22, on the module's security group, such as a jump host. Only useful with key\_name. Empty adds no ingress rule. | `list(string)` | `[]` | no |
| <a name="input_ssm_enabled"></a> [ssm\_enabled](#input\_ssm\_enabled) | Attach AmazonSSMManagedInstanceCore to the instance role, so people reach the instances through SSM Session Manager. With existing\_instance\_profile\_arn it is listed in required\_role\_policies instead. | `bool` | `true` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnets the instances launch in, ideally one per Availability Zone. The instances get no public address, so the subnets' routes (a NAT gateway, a proxy, a transit gateway) give them their way out. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_temporal_host"></a> [temporal\_host](#input\_temporal\_host) | Temporal frontend host:port the runner polls, set as TEMPORAL\_HOST: the internal runner load balancer on 7233 (the temporal\_address of compositions/aws's runner\_load\_balancer output). The runner dials it as Autoheal's hosted runners do, in plain gRPC with no key, so it must be a private address that only the network reaches. | `string` | n/a | yes |
| <a name="input_tool_response_callback_url"></a> [tool\_response\_callback\_url](#input\_tool\_response\_callback\_url) | URL the runner posts sandbox tool results to, set as SANDBOX\_TOOL\_RESPONSE\_CALLBACK\_URL: api-server-go's internal listener behind the runner load balancer (the tool\_response\_url of compositions/aws's runner\_load\_balancer output). Empty leaves it unset and tool results go through Temporal only. | `string` | `""` | no |
| <a name="input_tool_response_token_kms_key_arn"></a> [tool\_response\_token\_kms\_key\_arn](#input\_tool\_response\_token\_kms\_key\_arn) | ARN of the KMS key that encrypts tool\_response\_token\_secret\_arn. The instance role may decrypt with it only through Secrets Manager. Needed with tool\_response\_token\_secret\_arn. | `string` | `""` | no |
| <a name="input_tool_response_token_secret_arn"></a> [tool\_response\_token\_secret\_arn](#input\_tool\_response\_token\_secret\_arn) | ARN of the Secrets Manager secret that holds the callback key: the secret entry runner-callback-token of compositions/aws. Before each runner start the instance reads it with the instance role and writes it to a root-only file as SANDBOX\_TOOL\_RESPONSE\_CALLBACK\_TOKEN, so the key is never in the user data. Needs tool\_response\_token\_kms\_key\_arn. Empty sends no key. | `string` | `""` | no |
| <a name="input_trusted_ca_certificates"></a> [trusted\_ca\_certificates](#input\_trusted\_ca\_certificates) | PEM CA certificates the instances trust on top of the system ones: the private CA of an image registry such as a Nexus mirror, or of a proxy that inspects TLS. Each entry holds one or more certificates. cloud-init adds them to the system trust store before dnf installs packages and before Docker starts, so dnf, the Docker daemon (image pulls) and the ECR login trust them. runner-go and sandboxes do not get them. Certificates are public, not secrets. Empty adds none. | `list(string)` | `[]` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC of subnet\_ids, where the module's security group lives. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ami_id"></a> [ami\_id](#output\_ami\_id) | AMI the launch template uses: ami\_id, the newest ami\_name\_filter match, or the latest Amazon Linux 2023. |
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the runner Auto Scaling group. |
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the instance role the module creates. Empty with existing\_instance\_profile\_arn. |
| <a name="output_iam_role_name"></a> [iam\_role\_name](#output\_iam\_role\_name) | Name of the instance role the module creates, for attaching more policies outside the module. Empty with existing\_instance\_profile\_arn. |
| <a name="output_instance_profile_arn"></a> [instance\_profile\_arn](#output\_instance\_profile\_arn) | ARN of the instance profile the instances use: the module's, or existing\_instance\_profile\_arn. |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | ID of the runner launch template. |
| <a name="output_required_role_policies"></a> [required\_role\_policies](#output\_required\_role\_policies) | What the instance role needs: trust\_policy (JSON), inline\_policies (name => JSON; ecr-pull pulls from ecr\_registry\_host, then additional\_inline\_policies) and managed\_policy\_arns (name => ARN). The module attaches them to its own role; with existing\_instance\_profile\_arn the role's owner attaches them. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the instances' security group: the module's, or existing\_security\_group\_id. |
<!-- END_TF_DOCS -->
