# Autoheal BYOC — AWS ElastiCache for Redis

Node-based (provisioned) ElastiCache for Redis replication group for a BYOC-on-EKS
Autoheal install. `num_cache_clusters >= 2` gives a primary + replica with Multi-AZ
automatic failover (prod HA). Private: in the VPC private subnets, reachable only
from the security groups in `allowed_sg_ids` (the EKS node SG) on 6379; TLS in
transit and at-rest encryption on, access SG-restricted (no auth token by default).

The Azure analogue is `modules/azure/redis`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration wired to the `vpc`
module.

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
| [aws_elasticache_replication_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_replication_group) | resource |
| [aws_elasticache_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_subnet_group) | resource |
| [aws_security_group.redis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_sg_ids"></a> [allowed\_sg\_ids](#input\_allowed\_sg\_ids) | Security groups allowed to connect on 6379 (typically the EKS node/cluster SG). | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply modifications immediately instead of during the maintenance window. | `bool` | `false` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Redis engine version. | `string` | `"7.1"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'avid'. | `string` | `null` | no |
| <a name="input_node_type"></a> [node\_type](#input\_node\_type) | Node type (e.g. cache.t4g.small, cache.m7g.large). BYOC uses node-based/provisioned caches. | `string` | `"cache.m7g.large"` | no |
| <a name="input_num_cache_clusters"></a> [num\_cache\_clusters](#input\_num\_cache\_clusters) | Number of nodes. 1 = single node; >= 2 = primary + replica(s) with Multi-AZ automatic failover (prod HA). | `number` | `2` | no |
| <a name="input_replication_group_id_override"></a> [replication\_group\_id\_override](#input\_replication\_group\_id\_override) | Force an exact replication group id (<=40 chars). Empty = derive from the label id (truncated to 40). | `string` | `""` | no |
| <a name="input_snapshot_retention_limit"></a> [snapshot\_retention\_limit](#input\_snapshot\_retention\_limit) | Days to retain snapshots (0-35). | `number` | `1` | no |
| <a name="input_snapshot_window"></a> [snapshot\_window](#input\_snapshot\_window) | Daily snapshot window (UTC). | `string` | `"03:00-04:00"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnet ids for the cache subnet group (modules/aws/vpc output private\_subnet\_ids). | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr_block"></a> [vpc\_cidr\_block](#input\_vpc\_cidr\_block) | VPC CIDR for the SG egress rule. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the cache security group lives in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the replication group. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | primary\_endpoint:port. Maps to the cross-cloud output contract 'redis\_endpoint'. |
| <a name="output_port"></a> [port](#output\_port) | Redis port. |
| <a name="output_primary_endpoint_address"></a> [primary\_endpoint\_address](#output\_primary\_endpoint\_address) | Primary (writer) endpoint address. |
| <a name="output_reader_endpoint_address"></a> [reader\_endpoint\_address](#output\_reader\_endpoint\_address) | Reader endpoint address (empty for a single-node cache). |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group id of the cache. |
<!-- END_TF_DOCS -->
