# Autoheal BYOC — Azure Blob storage

Storage account + private container for attachments / knowledge-base objects in a
BYOC-on-AKS Autoheal install. The app reaches it keyless via the app workload
identity (Storage Blob Data Contributor, granted in
`modules/azure/workload-identity`); no account key is stored anywhere.

The AWS analogue is `modules/aws/s3`. Account names reject dashes and cap at 24
characters, so the module derives a sanitized name from the label id (override
available). Naming and tags follow the repo's null-label convention (see
`label.tf` and [docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

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
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.attachments](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_storage_management_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_management_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_name_override"></a> [account\_name\_override](#input\_account\_name\_override) | Force an exact storage account name (lowercase alphanumeric, <=24). Empty = derive a sanitized name from the label id. | `string` | `""` | no |
| <a name="input_account_replication_type"></a> [account\_replication\_type](#input\_account\_replication\_type) | Replication: LRS, ZRS, GRS, ... | `string` | `"LRS"` | no |
| <a name="input_account_tier"></a> [account\_tier](#input\_account\_tier) | Storage account tier. | `string` | `"Standard"` | no |
| <a name="input_allowed_ip_ranges"></a> [allowed\_ip\_ranges](#input\_allowed\_ip\_ranges) | Public IPs/CIDRs allowed through the storage firewall when default\_action=Deny (e.g. the Terraform apply host, which creates the container over the data plane). A /32 range is written as the bare address; /31 is not accepted by Azure Storage. | `list(string)` | `[]` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_blob_restore_days"></a> [blob\_restore\_days](#input\_blob\_restore\_days) | How far back point-in-time restore can rewind, in days. Must be LESS than blob\_soft\_delete\_retention\_days. Ignored when pitr\_enabled = false. | `number` | `6` | no |
| <a name="input_blob_soft_delete_retention_days"></a> [blob\_soft\_delete\_retention\_days](#input\_blob\_soft\_delete\_retention\_days) | Blob soft-delete retention in days (1-365). 0 = soft delete off. | `number` | `7` | no |
| <a name="input_cmk_identity_id"></a> [cmk\_identity\_id](#input\_cmk\_identity\_id) | User-assigned identity id used to reach the CMK key. Required when cmk\_key\_vault\_key\_id is set. | `string` | `""` | no |
| <a name="input_cmk_key_vault_key_id"></a> [cmk\_key\_vault\_key\_id](#input\_cmk\_key\_vault\_key\_id) | Key Vault key id for customer-managed encryption at rest. Empty = Microsoft-managed key (still encrypted). The vault must have purge protection on. | `string` | `""` | no |
| <a name="input_container_name"></a> [container\_name](#input\_container\_name) | Blob container name. | `string` | `"attachments"` | no |
| <a name="input_container_soft_delete_retention_days"></a> [container\_soft\_delete\_retention\_days](#input\_container\_soft\_delete\_retention\_days) | Container soft-delete retention in days (1-365). 0 = soft delete off. Protects the per-tenant Git Registry containers. | `number` | `7` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_network_default_action"></a> [network\_default\_action](#input\_network\_default\_action) | Storage firewall default action. Deny (recommended) = only the private endpoint, bypassed Azure services, and allowed\_ip\_ranges may reach the account. Use Allow only for playground accounts without a private endpoint. | `string` | `"Deny"` | no |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Delete noncurrent blob versions this many days after they become noncurrent (same default as modules/aws/s3). 0 = keep them forever. Ignored when versioning\_enabled = false. | `number` | `90` | no |
| <a name="input_pitr_enabled"></a> [pitr\_enabled](#input\_pitr\_enabled) | Enable point-in-time restore for block blobs (turns on the change feed and last-access tracking). Lets you rewind the account to an earlier moment. Recommended for production: true. | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the account lands in (created by the composition). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | Enable blob versioning on the account. The Git Registry expects it on (it is the Azure equivalent of the S3 bucket versioning the app sets on AWS). | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | Resource ID of the storage account. |
| <a name="output_account_name"></a> [account\_name](#output\_account\_name) | Storage account name. Maps to the cross-cloud output contract 'object\_store' (with container). |
| <a name="output_blob_endpoint"></a> [blob\_endpoint](#output\_blob\_endpoint) | Primary blob endpoint URL. |
| <a name="output_container_name"></a> [container\_name](#output\_container\_name) | Blob container name. |
<!-- END_TF_DOCS -->
