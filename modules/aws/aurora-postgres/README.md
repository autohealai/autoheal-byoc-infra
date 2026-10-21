# Autoheal BYOC: AWS Aurora PostgreSQL

Aurora PostgreSQL cluster for a BYOC-on-EKS Autoheal install: one writer plus
readers in the data subnets, no public access, storage and Performance Insights
encrypted with the caller's KMS key, and TLS required through `rds.force_ssl` in
the cluster parameter group.

The module creates its own security group (ingress on the database port only
from the allowed security groups and CIDRs), the DB subnet group, the cluster
parameter group (family from the major version), the Enhanced Monitoring role
and the CloudWatch log groups for exported logs. Deletion protection and a final
snapshot are on by default.

The Azure analogue is `modules/azure/postgres-flexible`. Naming and tags follow
the repo's null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Notes

- **Engine version.** The default `16.11` pins the minor version. With
  `auto_minor_version_upgrade = true` AWS still upgrades the minor version in
  the maintenance window; provider 6.59 and later then shows no diff instead of
  planning a downgrade. A major only value such as `16` also works: AWS picks
  the default minor for that major and Terraform keeps `16` in state, so minor
  upgrades never show as drift. AWS retires old minor versions, so a pinned
  minor may stop being available for new clusters; raise it when that happens.
- **Major upgrades.** Change `engine_version` to the new major and set
  `allow_major_version_upgrade = true` for that apply. The cluster parameter
  group name includes the family, so the new group is created first.
- **Serverless v2.** `instance_class = "db.serverless"` makes every instance a
  Serverless v2 instance. The cluster's scaling configuration is always set
  (AWS ignores it for provisioned instances), so switching in either direction
  is one apply.
- **Static parameters.** List static parameter names (for example
  `shared_preload_libraries`) in `cluster_parameters_pending_reboot`; they take
  effect after the next reboot.
- **Log encryption.** When `log_kms_key_arn` is set, its key policy must allow
  the CloudWatch Logs service (modules/aws/kms `cloudwatch_logs_enabled`).
- **Destroy.** Set `deletion_protection = false` and apply before a destroy. The
  final snapshot is named `<cluster>-final-<random hex>` unless
  `skip_final_snapshot = true`.

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.59, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.59, < 7.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | ../../_shared/label | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_role.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_rds_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_rds_cluster_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_parameter_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.from_cidr_blocks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_security_groups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_id.final_snapshot](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.monitoring_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allow_major_version_upgrade"></a> [allow\_major\_version\_upgrade](#input\_allow\_major\_version\_upgrade) | Allow a change of engine\_version to a new major version. Set it for the upgrade apply only. | `bool` | `false` | no |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | IPv4 CIDR blocks allowed to connect on the database port. | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | Security groups allowed to connect on the database port (for example the EKS cluster security group). | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply changes now instead of in the next maintenance window. Some changes restart the database. | `bool` | `false` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | Let AWS apply minor engine upgrades in the maintenance window. | `bool` | `true` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Days to keep automated backups (1-35). | `number` | `30` | no |
| <a name="input_ca_cert_identifier"></a> [ca\_cert\_identifier](#input\_ca\_cert\_identifier) | Certificate authority for the instances' server certificates. | `string` | `"rds-ca-rsa2048-g1"` | no |
| <a name="input_cluster_parameters"></a> [cluster\_parameters](#input\_cluster\_parameters) | Cluster parameter overrides, merged over the module defaults rds.force\_ssl = 1 and log\_min\_duration\_statement = 1000. | `map(string)` | `{}` | no |
| <a name="input_cluster_parameters_pending_reboot"></a> [cluster\_parameters\_pending\_reboot](#input\_cluster\_parameters\_pending\_reboot) | Names of static parameters in cluster\_parameters (for example shared\_preload\_libraries). They are applied with pending-reboot; all others apply immediately. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Block deletion of the cluster. Set false and apply before a destroy. | `bool` | `true` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_enabled_cloudwatch_logs_exports"></a> [enabled\_cloudwatch\_logs\_exports](#input\_enabled\_cloudwatch\_logs\_exports) | Log types to export to CloudWatch Logs. The module creates each log group first so it controls retention and encryption. | `list(string)` | <pre>[<br/>  "postgresql"<br/>]</pre> | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Aurora PostgreSQL version, "major.minor" (16.11) or major only (16). With a major only value AWS picks the default minor and Terraform keeps "16" in state, so automatic minor upgrades never show as drift. The parameter group family follows the major version. | `string` | `"16.11"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_iam_database_authentication_enabled"></a> [iam\_database\_authentication\_enabled](#input\_iam\_database\_authentication\_enabled) | Allow IAM database authentication in addition to passwords. | `bool` | `false` | no |
| <a name="input_instance_availability_zones"></a> [instance\_availability\_zones](#input\_instance\_availability\_zones) | Optional availability zones for the instances, used in order and repeated (instance N goes to zone N mod length). Empty lets AWS choose. Changing a zone replaces that instance. | `list(string)` | `[]` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | Instance class for every instance in the cluster. "db.serverless" makes them Serverless v2 instances sized by serverless\_min\_capacity and serverless\_max\_capacity. | `string` | `"db.r7g.large"` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of instances: one writer plus readers. Use 2 or more for automatic failover to another availability zone. | `number` | `2` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for storage, snapshots and Performance Insights. | `string` | n/a | yes |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_log_kms_key_arn"></a> [log\_kms\_key\_arn](#input\_log\_kms\_key\_arn) | KMS key ARN for the exported log groups. Empty uses CloudWatch Logs default encryption. The key policy must allow the CloudWatch Logs service. | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention in days for the exported log groups. | `number` | `365` | no |
| <a name="input_master_password"></a> [master\_password](#input\_master\_password) | Master user password, 8-128 printable ASCII characters except / " @ and space. The composition generates it and stores it in Secrets Manager. | `string` | n/a | yes |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Master user name. | `string` | `"pgadmin"` | no |
| <a name="input_monitoring_interval"></a> [monitoring\_interval](#input\_monitoring\_interval) | Enhanced Monitoring interval in seconds. 0 turns it off; otherwise the module creates the monitoring role. | `number` | `60` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_performance_insights_enabled"></a> [performance\_insights\_enabled](#input\_performance\_insights\_enabled) | Turn on Performance Insights (Database Insights standard mode) with 7 days of retention, encrypted with kms\_key\_arn. | `bool` | `true` | no |
| <a name="input_port"></a> [port](#input\_port) | Port the cluster listens on. | `number` | `5432` | no |
| <a name="input_preferred_backup_window"></a> [preferred\_backup\_window](#input\_preferred\_backup\_window) | Daily backup window in UTC (hh24:mi-hh24:mi). Must not overlap the maintenance window. | `string` | `"07:00-09:00"` | no |
| <a name="input_preferred_maintenance_window"></a> [preferred\_maintenance\_window](#input\_preferred\_maintenance\_window) | Weekly maintenance window in UTC (ddd:hh24:mi-ddd:hh24:mi), used by the cluster and its instances. | `string` | `"sun:09:30-sun:10:30"` | no |
| <a name="input_serverless_max_capacity"></a> [serverless\_max\_capacity](#input\_serverless\_max\_capacity) | Maximum Aurora capacity units per instance when instance\_class is db.serverless. | `number` | `16` | no |
| <a name="input_serverless_min_capacity"></a> [serverless\_min\_capacity](#input\_serverless\_min\_capacity) | Minimum Aurora capacity units per instance when instance\_class is db.serverless. 0 lets idle instances pause. | `number` | `0.5` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Skip the final snapshot on delete. When false the snapshot is named <cluster>-final-<random hex>. | `bool` | `false` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage\_type) | Storage configuration. Empty (or "aurora") is Aurora Standard; "aurora-iopt1" is Aurora I/O-Optimized. | `string` | `""` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnets for the DB subnet group (the VPC's data subnets). They must span at least two availability zones. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the cluster security group is created in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | Cluster ARN. |
| <a name="output_cluster_identifier"></a> [cluster\_identifier](#output\_cluster\_identifier) | Cluster identifier. |
| <a name="output_cluster_resource_id"></a> [cluster\_resource\_id](#output\_cluster\_resource\_id) | Cluster resource ID (cluster-...), used in rds-db:connect IAM policies. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Writer endpoint hostname. |
| <a name="output_master_username"></a> [master\_username](#output\_master\_username) | Master user name. |
| <a name="output_port"></a> [port](#output\_port) | Port the cluster listens on. |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | Reader endpoint hostname. It resolves to the writer while the cluster has no readers. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the cluster's security group. |
<!-- END_TF_DOCS -->
