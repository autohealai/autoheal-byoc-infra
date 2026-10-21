# Autoheal BYOC - AWS Network Load Balancer

Network Load Balancer (internal by default) with one TCP listener and one ip
target group per entry in `listeners`, e.g. Temporal on 7233 and the
api-server-go internal listener on 8083 for the runner. The module registers no
targets: the AWS Load Balancer Controller registers pod IPs through the
TargetGroupBinding resources the chart renders from `target_group_arns`. Client
IP preservation stays off, so targets see the NLB's own address.

The NLB has its own security group: ingress on each listener port from
`allowed_cidr_blocks` and `allowed_security_group_ids`, egress to the VPC CIDR
on the target and health check ports. `target_security_group_ids` (for example
the EKS cluster security group) get an ingress rule from the NLB security group
on those ports. Rules are keyed by list position, so IDs created in the same
apply can be passed in. NLB and target group names are cut to 32 characters
with a hash suffix. Naming and tags follow the repo's null-label convention (see
`label.tf` and [docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

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
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cidr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_logs_bucket"></a> [access\_logs\_bucket](#input\_access\_logs\_bucket) | S3 bucket for NLB access logs. Empty turns access logs off. NLB access logs only cover TLS listeners, so with the TCP listeners of this module the bucket receives nothing. | `string` | `""` | no |
| <a name="input_access_logs_prefix"></a> [access\_logs\_prefix](#input\_access\_logs\_prefix) | Key prefix for the access logs in access\_logs\_bucket. Empty writes to the bucket root. | `string` | `""` | no |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | IPv4 CIDRs allowed to connect to every listener port. | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | Security groups allowed to connect to every listener port, e.g. the runner security group. IDs may be created in the same apply. | `list(string)` | `[]` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_cross_zone_enabled"></a> [cross\_zone\_enabled](#input\_cross\_zone\_enabled) | Spread traffic across targets in all enabled Availability Zones. Off, each NLB node only sends to targets in its own zone, and a zone with no ready pod drops the connections it receives. | `bool` | `true` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Block deletion of the NLB through the AWS API. When true, set it to false and apply before a destroy. | `bool` | `false` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_internal"></a> [internal](#input\_internal) | true for an internal NLB with private addresses only. false makes it internet-facing (public subnets needed). | `bool` | `true` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_listeners"></a> [listeners](#input\_listeners) | Listeners keyed by a stable name, e.g. temporal. Each gets a TCP listener on port and an ip target group on target\_port (default: port). health\_check.path applies to HTTP and HTTPS checks only (default /). health\_check.port is traffic-port or a port number. The health check timeout is set from the protocol default (6 seconds for HTTP, 10 otherwise) and kept below the interval. | <pre>map(object({<br/>    port                 = number<br/>    target_port          = optional(number)<br/>    protocol             = optional(string, "TCP")<br/>    deregistration_delay = optional(number, 30)<br/>    health_check = optional(object({<br/>      protocol            = optional(string, "TCP")<br/>      path                = optional(string, "")<br/>      port                = optional(string, "traffic-port")<br/>      interval            = optional(number, 10)<br/>      healthy_threshold   = optional(number, 3)<br/>      unhealthy_threshold = optional(number, 3)<br/>    }), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnets the load balancer gets a node in, one per Availability Zone (private subnets for an internal NLB). Subnets can be added later but removing one replaces the NLB. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_target_security_group_ids"></a> [target\_security\_group\_ids](#input\_target\_security\_group\_ids) | Security groups of the targets, e.g. the EKS cluster security group the pods use. Each gets an ingress rule from the NLB security group on the target and health check ports. Leave empty when the targets already allow that traffic. IDs may be created in the same apply. | `list(string)` | `[]` | no |
| <a name="input_vpc_cidr_block"></a> [vpc\_cidr\_block](#input\_vpc\_cidr\_block) | IPv4 CIDR of the VPC. The NLB security group allows egress to it on the target and health check ports, where the pod IP targets live. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the load balancer, its security group and the target groups live in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the NLB. |
| <a name="output_arn_suffix"></a> [arn\_suffix](#output\_arn\_suffix) | ARN suffix of the NLB, the LoadBalancer dimension of its CloudWatch metrics. |
| <a name="output_dns_name"></a> [dns\_name](#output\_dns\_name) | DNS name of the NLB, e.g. for temporal\_host (<dns\_name>:7233) or a Route 53 alias. |
| <a name="output_listener_arns"></a> [listener\_arns](#output\_listener\_arns) | Listener ARNs keyed like var.listeners. |
| <a name="output_name"></a> [name](#output\_name) | Name of the NLB. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the NLB security group. |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Target group ARNs keyed like var.listeners, for the chart's TargetGroupBinding resources. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | Route 53 hosted zone ID of the NLB, for alias records. |
<!-- END_TF_DOCS -->
