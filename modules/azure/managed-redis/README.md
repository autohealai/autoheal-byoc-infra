# Autoheal BYOC - Azure Managed Redis

Azure Managed Redis (`Microsoft.Cache/redisEnterprise`) with public network
access off. The composition reaches it through a private endpoint. Clients use
TLS on port 10000. `public_network_access_enabled = true` opens the public
endpoint instead; Azure Managed Redis has no IP firewall, so the access key and
TLS then protect it.

The defaults fit test subscriptions: SKU `Balanced_B0`, no high availability,
`EnterpriseCluster` clustering, `Encrypted` client protocol and access-key
authentication on. The AWS analogue is ElastiCache. Naming and tags follow the
repo's null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

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
| [azurerm_managed_redis.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_redis) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_keys_authentication_enabled"></a> [access\_keys\_authentication\_enabled](#input\_access\_keys\_authentication\_enabled) | Allow access-key authentication. The services read the key from the vault entry the composition writes, so keep this on unless they authenticate with Entra. | `bool` | `true` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_client_protocol"></a> [client\_protocol](#input\_client\_protocol) | Encrypted (TLS) or Plaintext. | `string` | `"Encrypted"` | no |
| <a name="input_clustering_policy"></a> [clustering\_policy](#input\_clustering\_policy) | EnterpriseCluster (single endpoint, works with non-cluster clients), OSSCluster or NoCluster. | `string` | `"EnterpriseCluster"` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_eviction_policy"></a> [eviction\_policy](#input\_eviction\_policy) | Eviction policy for the default database. | `string` | `"VolatileLRU"` | no |
| <a name="input_high_availability_enabled"></a> [high\_availability\_enabled](#input\_high\_availability\_enabled) | Run a replica for automatic failover. Off by default to fit test subscriptions; turn on for production. | `bool` | `false` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Open the public endpoint. Azure Managed Redis has no IP firewall, so any address can then reach it; the access key and TLS still apply. Off: reach it through a private endpoint. | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the cache lands in. | `string` | n/a | yes |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | Managed Redis SKU, e.g. Balanced\_B0, Balanced\_B1, MemoryOptimized\_M10. Balanced\_B0 is the smallest and the one test subscriptions allow. | `string` | `"Balanced_B0"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_hostname"></a> [hostname](#output\_hostname) | Host clients connect to, <name>.<region>.redis.azure.net. |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the cache. |
| <a name="output_name"></a> [name](#output\_name) | Name of the cache. |
| <a name="output_port"></a> [port](#output\_port) | TLS port of the default database (10000). |
| <a name="output_primary_access_key"></a> [primary\_access\_key](#output\_primary\_access\_key) | Primary access key of the default database. |
<!-- END_TF_DOCS -->
