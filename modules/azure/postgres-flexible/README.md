# Autoheal BYOC — Azure PostgreSQL Flexible Server

Provisioned, private (VNet-integrated) PostgreSQL Flexible Server for a
BYOC-on-AKS Autoheal install. No public endpoint: it attaches to the PG-delegated
subnet and the private DNS zone created by `modules/azure/vnet`, so it is
reachable only from inside the VNet (AKS pods).

Sets the `azure.extensions` server configuration so `CREATE EXTENSION` (pgvector,
btree_gin, pg_trgm, ...) succeeds. Azure Flexible rejects any extension not
pre-listed, a gap RDS did not have.

The AWS analogue is `modules/aws/rds-cluster`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration wired to the
`vnet` module.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | ../../_shared/label | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_postgresql_flexible_server.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server) | resource |
| [azurerm_postgresql_flexible_server_configuration.extensions](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_configuration) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_administrator_login"></a> [administrator\_login](#input\_administrator\_login) | Server admin username. | `string` | `"pgadmin"` | no |
| <a name="input_administrator_password"></a> [administrator\_password](#input\_administrator\_password) | Admin password. The composition generates one and also seeds it into Key Vault for ESO; never commit a real value. | `string` | n/a | yes |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_delegated_subnet_id"></a> [delegated\_subnet\_id](#input\_delegated\_subnet\_id) | VNet subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers (private, no public access). Use modules/azure/vnet output subnet\_db\_id. | `string` | n/a | yes |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_extensions"></a> [extensions](#input\_extensions) | Extensions added to azure.extensions. Every extension must be allow-listed here BEFORE any CREATE EXTENSION runs; Azure Flexible enforces this where RDS did not. VECTOR=pgvector, BTREE\_GIN=Temporal advanced-visibility. | `list(string)` | <pre>[<br/>  "VECTOR",<br/>  "BTREE_GIN",<br/>  "PG_TRGM",<br/>  "HSTORE",<br/>  "UUID-OSSP"<br/>]</pre> | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_postgres_version"></a> [postgres\_version](#input\_postgres\_version) | Major PostgreSQL version. | `string` | `"16"` | no |
| <a name="input_private_dns_zone_id"></a> [private\_dns\_zone\_id](#input\_private\_dns\_zone\_id) | Private DNS zone id for the server FQDN. Use modules/azure/vnet output pg\_private\_dns\_zone\_id. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the server lands in (created by the composition). | `string` | n/a | yes |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | azurerm combined tier+size (e.g. GP\_Standard\_D2ds\_v5, MO\_Standard\_E2ds\_v5). BYOC policy = provisioned (GP\_/MO\_), never Burstable (B\_), for a real install. | `string` | `"GP_Standard_D2ds_v5"` | no |
| <a name="input_storage_mb"></a> [storage\_mb](#input\_storage\_mb) | Storage size in MB. | `number` | `32768` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_administrator_login"></a> [administrator\_login](#output\_administrator\_login) | Server admin username. |
| <a name="output_host"></a> [host](#output\_host) | Server FQDN (resolves privately via the VNet-linked DNS zone). Maps to the cross-cloud output contract 'postgres\_host'. |
| <a name="output_name"></a> [name](#output\_name) | Server name. |
| <a name="output_port"></a> [port](#output\_port) | PostgreSQL port. |
| <a name="output_server_id"></a> [server\_id](#output\_server\_id) | Resource ID of the Flexible Server. |
<!-- END_TF_DOCS -->
