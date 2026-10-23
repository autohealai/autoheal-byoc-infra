# Autoheal BYOC - AWS VPC

VPC for a BYOC-on-EKS Autoheal install, spread over 2 to 6 availability zones
with one subnet per zone in each tier:

| Tier | Holds | Default route |
|------|-------|---------------|
| public | NAT gateways, internet-facing load balancers (`kubernetes.io/role/elb=1`) | internet gateway |
| private | EKS control plane ENIs, nodes and pods (`kubernetes.io/role/internal-elb=1`) | NAT gateway of the zone |
| data (optional) | Aurora, ElastiCache | none |

Public subnets do not assign public IPs on launch. When `cluster_name` is set,
public and private subnets also get `kubernetes.io/cluster/<name>=shared`; data
subnets never do, so load balancers stay out of them.

`nat_gateway_mode`:

- `per_az` (default): one NAT gateway per zone. A zone outage only affects that zone.
- `single`: one NAT gateway in the first zone. Cheaper; a zone outage there cuts
  egress for every zone.
- `none`: no internet egress. Add `interface_endpoints` for the AWS APIs the
  cluster needs and pull images through a mirror or ECR pull-through cache.

The S3 gateway endpoint (on by default) is attached to the private and data
route tables. Interface endpoints go in the private subnets of the zones the
service is offered in, with private DNS on and one shared security group
allowing 443 from the VPC CIDR.

Flow logs (on by default) go to `/aws/vpc/<label id>/flow-logs` through an IAM
role only the flow logs service in this account can assume. To encrypt the log
group with a customer managed key, pass `flow_logs_kms_key_arn` from
`modules/aws/kms` with `cloudwatch_logs_enabled = true`.

Routes are separate `aws_route` resources, so callers can add their own
(peering, transit gateway) to the route table outputs.

The Azure analogue is `modules/azure/vnet`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
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
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_ingress_rule.endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_vpc_endpoint_service.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc_endpoint_service) | data source |
| [aws_vpc_endpoint_service.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc_endpoint_service) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zone names to spread subnets over, e.g. ["us-west-2a", "us-west-2b", "us-west-2c"]. 2 to 6 zones. Each subnet list is indexed in this order. | `list(string)` | n/a | yes |
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | IPv4 CIDR of the VPC, e.g. 10.0.0.0/16. All subnet CIDRs must fall inside it. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name. When set, public and private subnets get the kubernetes.io/cluster/<name>=shared tag. Data subnets never get it, so load balancers stay out of them. | `string` | `""` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_data_subnet_cidrs"></a> [data\_subnet\_cidrs](#input\_data\_subnet\_cidrs) | Empty, or one CIDR per availability zone for the data subnets (Aurora and ElastiCache). Their route table has no internet route. | `list(string)` | `[]` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_flow_logs_enabled"></a> [flow\_logs\_enabled](#input\_flow\_logs\_enabled) | Send VPC flow logs to a CloudWatch log group created by the module. | `bool` | `true` | no |
| <a name="input_flow_logs_kms_key_arn"></a> [flow\_logs\_kms\_key\_arn](#input\_flow\_logs\_kms\_key\_arn) | KMS key ARN to encrypt the flow log group. The key policy must let the CloudWatch Logs service use it (modules/aws/kms cloudwatch\_logs\_enabled = true). Empty uses CloudWatch Logs default encryption. | `string` | `""` | no |
| <a name="input_flow_logs_retention_days"></a> [flow\_logs\_retention\_days](#input\_flow\_logs\_retention\_days) | Retention of the flow log group in days. Must be a value CloudWatch Logs accepts; 0 keeps logs forever. | `number` | `365` | no |
| <a name="input_flow_logs_traffic_type"></a> [flow\_logs\_traffic\_type](#input\_flow\_logs\_traffic\_type) | Which traffic the flow logs record: ALL, ACCEPT or REJECT. | `string` | `"ALL"` | no |
| <a name="input_interface_endpoints"></a> [interface\_endpoints](#input\_interface\_endpoints) | Short AWS service names to create interface endpoints for, e.g. ["ecr.api", "ecr.dkr", "sts", "logs"]. They go in the private subnets with private DNS on and share one security group that allows 443 from the VPC CIDR. Use s3\_gateway\_endpoint\_enabled for S3. | `list(string)` | `[]` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_nat_gateway_mode"></a> [nat\_gateway\_mode](#input\_nat\_gateway\_mode) | NAT gateway layout: per\_az (one per zone, survives a zone outage), single (one in the first zone, cheaper, zone outage cuts egress) or none (no internet egress; use interface\_endpoints for AWS APIs and a pull-through cache or mirror for images). | `string` | `"per_az"` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | One CIDR per availability zone for the private subnets (EKS nodes and pods). Size these generously: with the VPC CNI every pod takes a VPC IP. | `list(string)` | n/a | yes |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | One CIDR per availability zone for the public subnets (NAT gateways and internet-facing load balancers). A /24 or smaller is enough. | `list(string)` | n/a | yes |
| <a name="input_s3_gateway_endpoint_enabled"></a> [s3\_gateway\_endpoint\_enabled](#input\_s3\_gateway\_endpoint\_enabled) | Create an S3 gateway endpoint on the private and data route tables. Free, and keeps S3 traffic off NAT. | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_availability_zones"></a> [availability\_zones](#output\_availability\_zones) | Availability zones the subnets are spread over, in the order of every subnet list output. |
| <a name="output_data_route_table_id"></a> [data\_route\_table\_id](#output\_data\_route\_table\_id) | ID of the data route table (no internet route). Empty when data\_subnet\_cidrs is empty. |
| <a name="output_data_subnet_ids"></a> [data\_subnet\_ids](#output\_data\_subnet\_ids) | Data subnet IDs (Aurora and ElastiCache), one per availability zone. Empty when data\_subnet\_cidrs is empty. |
| <a name="output_flow_log_group_name"></a> [flow\_log\_group\_name](#output\_flow\_log\_group\_name) | Name of the CloudWatch log group that receives VPC flow logs. Empty when flow\_logs\_enabled is false. |
| <a name="output_interface_endpoint_security_group_id"></a> [interface\_endpoint\_security\_group\_id](#output\_interface\_endpoint\_security\_group\_id) | ID of the security group shared by the interface endpoints. Empty when interface\_endpoints is empty. |
| <a name="output_nat_gateway_public_ips"></a> [nat\_gateway\_public\_ips](#output\_nat\_gateway\_public\_ips) | Public IPs of the NAT gateways, i.e. the egress IPs to allowlist on external services. Empty when nat\_gateway\_mode is none. |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | Private route table IDs, one per availability zone. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs (EKS nodes and pods), one per availability zone. |
| <a name="output_public_route_table_id"></a> [public\_route\_table\_id](#output\_public\_route\_table\_id) | ID of the public route table. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs (NAT gateways and internet-facing load balancers), one per availability zone. |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | IPv4 CIDR of the VPC. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC. |
<!-- END_TF_DOCS -->
