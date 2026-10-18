# Autoheal BYOC — Azure VNet

Network substrate for a BYOC-on-AKS Autoheal install. Creates a VNet with four
purpose-built subnets (AKS nodes, PG-delegated, private endpoints, runner VMSS),
a NAT gateway for runner egress, the PostgreSQL Flexible
Server private DNS zone, and optional privatelink DNS zones for Blob, Key Vault,
and AI Foundry / Azure OpenAI. When `temporal_ip` is set, an NSG on the AKS
subnet lets only the runner subnet reach that address on ports 7233 (Temporal)
and 8083 (the api-server-go internal listener for tool results).

The AWS analogue is `modules/aws/vpc`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
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
| [azurerm_nat_gateway.runner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway) | resource |
| [azurerm_nat_gateway_public_ip_association.runner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway_public_ip_association) | resource |
| [azurerm_network_security_group.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_private_dns_zone.pe](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone.pg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.pe](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_dns_zone_virtual_network_link.pg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_public_ip.runner_nat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_subnet.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.db](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.pe](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.runner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_nat_gateway_association.runner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_nat_gateway_association) | resource |
| [azurerm_subnet_network_security_group_association.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | VNet address space. | `list(string)` | <pre>[<br/>  "10.60.0.0/16"<br/>]</pre> | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_foundry_private_endpoint_enabled"></a> [foundry\_private\_endpoint\_enabled](#input\_foundry\_private\_endpoint\_enabled) | Create privatelink DNS zones + VNet links for an AI Foundry / Azure OpenAI private endpoint (openai + cognitiveservices + services.ai suffixes). | `bool` | `false` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the VNet and its NAT gateway. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_pg_private_dns_zone_name"></a> [pg\_private\_dns\_zone\_name](#input\_pg\_private\_dns\_zone\_name) | Private DNS zone name for PG Flexible Server. Empty disables the zone (connect installs that bring their own). Must end in .private.postgres.database.azure.com. | `string` | `""` | no |
| <a name="input_private_endpoints_enabled"></a> [private\_endpoints\_enabled](#input\_private\_endpoints\_enabled) | Create privatelink DNS zones + VNet links for Blob and Key Vault private endpoints. | `bool` | `false` | no |
| <a name="input_redis_private_endpoint_enabled"></a> [redis\_private\_endpoint\_enabled](#input\_redis\_private\_endpoint\_enabled) | Create the privatelink DNS zone + VNet link for an Azure Managed Redis private endpoint (privatelink.redis.azure.net). | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the network lands in (created by the composition). | `string` | n/a | yes |
| <a name="input_runner_nat_enabled"></a> [runner\_nat\_enabled](#input\_runner\_nat\_enabled) | Create a NAT gateway for outbound egress on the runner subnet (the runner VMSS has no public IP). | `bool` | `true` | no |
| <a name="input_subnet_aks_prefix"></a> [subnet\_aks\_prefix](#input\_subnet\_aks\_prefix) | Subnet for AKS nodes/pods (overlay CNI, so this only sizes nodes). | `string` | `"10.60.0.0/20"` | no |
| <a name="input_subnet_db_prefix"></a> [subnet\_db\_prefix](#input\_subnet\_db\_prefix) | Subnet delegated to PostgreSQL Flexible Server. | `string` | `"10.60.16.0/24"` | no |
| <a name="input_subnet_pe_prefix"></a> [subnet\_pe\_prefix](#input\_subnet\_pe\_prefix) | Subnet for private endpoints (KV/Blob/Foundry when private). | `string` | `"10.60.17.0/24"` | no |
| <a name="input_subnet_runner_prefix"></a> [subnet\_runner\_prefix](#input\_subnet\_runner\_prefix) | Dedicated subnet for the runner VMSS (DooD job runners), isolated from AKS nodes. | `string` | `"10.60.19.0/24"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_temporal_ip"></a> [temporal\_ip](#input\_temporal\_ip) | Reserved internal address of the Temporal load balancer in the AKS subnet. The chart also puts the api-server-go internal listener (port 8083) on it. When set, an NSG on the AKS subnet lets only the runner subnet reach this address on ports 7233 and 8083. Empty creates no NSG. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aks_nsg_id"></a> [aks\_nsg\_id](#output\_aks\_nsg\_id) | Resource ID of the AKS subnet NSG, or empty when temporal\_ip is not set. |
| <a name="output_aks_nsg_name"></a> [aks\_nsg\_name](#output\_aks\_nsg\_name) | Name of the AKS subnet NSG, or empty when temporal\_ip is not set. |
| <a name="output_blob_private_dns_zone_id"></a> [blob\_private\_dns\_zone\_id](#output\_blob\_private\_dns\_zone\_id) | Privatelink DNS zone id for Blob, or empty when private endpoints are off. |
| <a name="output_foundry_private_dns_zone_ids"></a> [foundry\_private\_dns\_zone\_ids](#output\_foundry\_private\_dns\_zone\_ids) | Privatelink DNS zone ids for AI Foundry / Azure OpenAI, or [] when the Foundry endpoint is off. |
| <a name="output_pg_private_dns_zone_id"></a> [pg\_private\_dns\_zone\_id](#output\_pg\_private\_dns\_zone\_id) | Private DNS zone id for PG Flexible Server, or empty when no zone was created. |
| <a name="output_redis_private_dns_zone_id"></a> [redis\_private\_dns\_zone\_id](#output\_redis\_private\_dns\_zone\_id) | Privatelink DNS zone id for Azure Managed Redis, or empty when the Redis endpoint is off. |
| <a name="output_runner_nat_public_ip"></a> [runner\_nat\_public\_ip](#output\_runner\_nat\_public\_ip) | Static egress IP of the runner subnet's NAT gateway (for outbound allowlisting), or empty when NAT is off. |
| <a name="output_subnet_aks_id"></a> [subnet\_aks\_id](#output\_subnet\_aks\_id) | Subnet ID for AKS nodes/pods. |
| <a name="output_subnet_db_id"></a> [subnet\_db\_id](#output\_subnet\_db\_id) | Subnet ID delegated to PostgreSQL Flexible Server. |
| <a name="output_subnet_pe_id"></a> [subnet\_pe\_id](#output\_subnet\_pe\_id) | Subnet ID for private endpoints. |
| <a name="output_subnet_runner_id"></a> [subnet\_runner\_id](#output\_subnet\_runner\_id) | Subnet ID for the runner VMSS. |
| <a name="output_vault_private_dns_zone_id"></a> [vault\_private\_dns\_zone\_id](#output\_vault\_private\_dns\_zone\_id) | Privatelink DNS zone id for Key Vault, or empty when private endpoints are off. |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | Resource ID of the VNet. |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | Name of the VNet. |
<!-- END_TF_DOCS -->
