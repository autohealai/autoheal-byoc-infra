# Autoheal BYOC — AWS Aurora PostgreSQL (provisioned)

Provisioned Aurora PostgreSQL cluster (writer + optional reader) for a BYOC-on-EKS
Autoheal install. BYOC policy is provisioned (e.g. `db.r7g.large`), never Serverless
v2 or burstable, for a real install. Private: reachable only from the security groups
in `allowed_sg_ids` (the EKS node SG) on 5432; storage encrypted.

The master password is generated and seeded into Secrets Manager by the composition
(this module takes it as a sensitive input, staying aws-only). The Azure analogue is
`modules/azure/postgres-flexible`. Naming and tags follow the repo's null-label
convention (see `label.tf` and
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
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_rds_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_rds_cluster_instance.writer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_security_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_sg_ids"></a> [allowed\_sg\_ids](#input\_allowed\_sg\_ids) | Security groups allowed to connect on 5432 (typically the EKS node/cluster SG). | `list(string)` | `[]` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Days to retain automated backups. | `number` | `7` | no |
| <a name="input_backup_window"></a> [backup\_window](#input\_backup\_window) | Preferred backup window (UTC). | `string` | `"01:00-02:00"` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | Initial database name. | `string` | `"autoheal"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Enable deletion protection (set true for prod). When false, no final snapshot is taken on destroy. | `bool` | `false` | no |
| <a name="input_enable_performance_insights"></a> [enable\_performance\_insights](#input\_enable\_performance\_insights) | Enable Performance Insights on the instances. | `bool` | `true` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Aurora PostgreSQL engine version. | `string` | `"16.6"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | Provisioned instance class for the writer/reader. BYOC policy = provisioned (db.r7g.* / db.r8g.*), never db.serverless, for a real install. | `string` | `"db.r7g.large"` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Preferred maintenance window (UTC). | `string` | `"mon:03:00-mon:04:00"` | no |
| <a name="input_master_password"></a> [master\_password](#input\_master\_password) | Master password. The composition generates one and also seeds it into Secrets Manager; never commit a real value. | `string` | n/a | yes |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Master username. | `string` | `"pgadmin"` | no |
| <a name="input_multi_az"></a> [multi\_az](#input\_multi\_az) | Add a reader instance in a second AZ for HA failover. | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'avid'. | `string` | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnet ids for the DB subnet group (modules/aws/vpc output private\_subnet\_ids). | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr_block"></a> [vpc\_cidr\_block](#input\_vpc\_cidr\_block) | VPC CIDR for the SG egress rule. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the cluster security group lives in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_administrator_login"></a> [administrator\_login](#output\_administrator\_login) | Master username. |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | Cluster ARN. |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | Cluster identifier. |
| <a name="output_database_name"></a> [database\_name](#output\_database\_name) | Initial database name. |
| <a name="output_host"></a> [host](#output\_host) | Writer endpoint (private). Maps to the cross-cloud output contract 'postgres\_host'. |
| <a name="output_port"></a> [port](#output\_port) | PostgreSQL port. |
| <a name="output_reader_host"></a> [reader\_host](#output\_reader\_host) | Reader endpoint. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group id of the cluster (reference it from clients). |
<!-- END_TF_DOCS -->
