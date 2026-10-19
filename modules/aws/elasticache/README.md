# Autoheal BYOC: AWS ElastiCache (Valkey)

ElastiCache replication group for a BYOC-on-EKS Autoheal install, cluster mode
disabled: one primary plus read replicas with Multi-AZ automatic failover.
Valkey by default; Redis OSS 6.2 and later is also supported.

Clients must use TLS and the AUTH token. Data at rest and snapshots are
encrypted with the caller's KMS key. Slow log and engine log go to CloudWatch log
groups the module creates. The module also creates its own security group
(ingress on the cache port only from the allowed security groups and CIDRs), the
subnet group and a parameter group whose family follows the engine and major
version (`valkey8`, `redis7`).

The Azure analogue is `modules/azure/managed-redis`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Notes

- **AUTH token characters.** AWS accepts letters, digits and only the symbols
  `! & # $ ^ < > -`. When generating it with `random_password`, set
  `override_special = "!&#$^<>-"`.
- **Token rotation.** With the default `auth_token_update_strategy = "ROTATE"`, a
  new token is added and the old one keeps working, so clients can move over.
  Apply again with `SET` to drop the old token.
- **Single node.** For one node set `num_cache_clusters = 1`,
  `automatic_failover_enabled = false` and `multi_az_enabled = false`.
- **Replacement.** Changing `kms_key_arn` or moving to an older engine version
  replaces the replication group, which empties the cache.
- **Log encryption.** When `log_kms_key_arn` is set, its key policy must allow
  the CloudWatch Logs service (modules/aws/kms `cloudwatch_logs_enabled`).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.58, < 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.58, < 7.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | ../../_shared/label | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_elasticache_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_parameter_group) | resource |
| [aws_elasticache_replication_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_replication_group) | resource |
| [aws_elasticache_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_subnet_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.from_cidr_blocks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_security_groups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | IPv4 CIDR blocks allowed to connect on the cache port. | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | Security groups allowed to connect on the cache port (for example the EKS cluster security group). | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply changes now instead of in the next maintenance window. | `bool` | `false` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_auth_token"></a> [auth\_token](#input\_auth\_token) | AUTH token clients must send, 16-128 characters. Letters, digits and only these symbols: ! & # $ ^ < > -. | `string` | n/a | yes |
| <a name="input_auth_token_update_strategy"></a> [auth\_token\_update\_strategy](#input\_auth\_token\_update\_strategy) | How a changed auth\_token is applied. ROTATE accepts both the old and new token until the next change with SET; SET accepts only the new token. | `string` | `"ROTATE"` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | Let AWS apply minor engine upgrades in the maintenance window. | `bool` | `true` | no |
| <a name="input_automatic_failover_enabled"></a> [automatic\_failover\_enabled](#input\_automatic\_failover\_enabled) | Promote a replica when the primary fails. Needs num\_cache\_clusters >= 2. | `bool` | `true` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | Cache engine: valkey or redis. | `string` | `"valkey"` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Engine version as major.minor (Valkey 7.2 or later, Redis OSS 6.2 or later). The parameter group family follows the engine and major version (valkey8, redis7). | `string` | `"8.2"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for encryption at rest, including snapshots. Changing it replaces the replication group. | `string` | n/a | yes |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_log_kms_key_arn"></a> [log\_kms\_key\_arn](#input\_log\_kms\_key\_arn) | KMS key ARN for the log groups. Empty uses CloudWatch Logs default encryption. The key policy must allow the CloudWatch Logs service. | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention in days for the slow-log and engine-log log groups. | `number` | `365` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Weekly maintenance window in UTC (ddd:hh24:mi-ddd:hh24:mi). | `string` | `"sun:06:30-sun:07:30"` | no |
| <a name="input_multi_az_enabled"></a> [multi\_az\_enabled](#input\_multi\_az\_enabled) | Place replicas in other availability zones and fail over across zones. Needs automatic\_failover\_enabled and num\_cache\_clusters >= 2. | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_node_type"></a> [node\_type](#input\_node\_type) | Node type for every node in the group. | `string` | `"cache.m7g.large"` | no |
| <a name="input_num_cache_clusters"></a> [num\_cache\_clusters](#input\_num\_cache\_clusters) | Number of nodes: one primary plus read replicas (1-6). Automatic failover and Multi-AZ need at least 2. | `number` | `2` | no |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | Parameter overrides for the module's parameter group (for example maxmemory-policy). | `map(string)` | `{}` | no |
| <a name="input_port"></a> [port](#input\_port) | Port the cache listens on. | `number` | `6379` | no |
| <a name="input_snapshot_retention_limit"></a> [snapshot\_retention\_limit](#input\_snapshot\_retention\_limit) | Days to keep automatic snapshots (0-35). 0 turns snapshots off. | `number` | `7` | no |
| <a name="input_snapshot_window"></a> [snapshot\_window](#input\_snapshot\_window) | Daily snapshot window in UTC (hh24:mi-hh24:mi). Must not overlap the maintenance window. | `string` | `"05:00-06:00"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnets for the cache subnet group (the VPC's data subnets). Use subnets in at least two availability zones for Multi-AZ. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the cache security group is created in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | Replication group ARN. |
| <a name="output_port"></a> [port](#output\_port) | Port the cache listens on. |
| <a name="output_primary_endpoint_address"></a> [primary\_endpoint\_address](#output\_primary\_endpoint\_address) | Primary (read and write) endpoint hostname. Clients connect with TLS and the AUTH token. |
| <a name="output_reader_endpoint_address"></a> [reader\_endpoint\_address](#output\_reader\_endpoint\_address) | Reader endpoint hostname. It spreads reads over the replicas and resolves to the primary when there are none. |
| <a name="output_replication_group_id"></a> [replication\_group\_id](#output\_replication\_group\_id) | Replication group ID. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the cache's security group. |
<!-- END_TF_DOCS -->
