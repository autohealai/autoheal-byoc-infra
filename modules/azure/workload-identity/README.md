# Autoheal BYOC — Azure Workload Identity

User-assigned identity federated to the app's Kubernetes service accounts (via the
AKS OIDC issuer), so pods get Entra tokens with no stored credentials. Role
assignments grant exactly what the app needs: Key Vault Secrets User (ESO), Blob
Data Contributor, and optionally AcrPull.

The AWS analogue is EKS Pod Identity / IRSA. Naming and tags follow the repo's
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
| [azurerm_federated_identity_credential.sa](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.acr_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.blob_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.kv_secrets_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acr_id"></a> [acr\_id](#input\_acr\_id) | ACR to grant AcrPull when acr\_pull\_enabled is true (kubelet identity usually covers pulls; set only if the app itself pulls). | `string` | `""` | no |
| <a name="input_acr_pull_enabled"></a> [acr\_pull\_enabled](#input\_acr\_pull\_enabled) | Assign AcrPull on var.acr\_id. Plan-time bool: acr\_id is often a computed id, so it cannot gate count directly. | `bool` | `false` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_blob_role_enabled"></a> [blob\_role\_enabled](#input\_blob\_role\_enabled) | Assign Storage Blob Data Contributor on var.storage\_account\_id. Plan-time bool: storage\_account\_id is a computed id, so it cannot gate count directly. | `bool` | `true` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_federated_service_accounts"></a> [federated\_service\_accounts](#input\_federated\_service\_accounts) | Kubernetes service accounts federated to this identity (subject system:serviceaccount:<ns>:<sa>). | <pre>list(object({<br/>    namespace       = string<br/>    service_account = string<br/>  }))</pre> | n/a | yes |
| <a name="input_key_vault_id"></a> [key\_vault\_id](#input\_key\_vault\_id) | Key Vault to grant Key Vault Secrets User (ESO reads secrets). | `string` | `""` | no |
| <a name="input_kv_role_enabled"></a> [kv\_role\_enabled](#input\_kv\_role\_enabled) | Assign Key Vault Secrets User on var.key\_vault\_id. Plan-time bool: key\_vault\_id is a computed id, so it cannot gate count directly. | `bool` | `true` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | AKS OIDC issuer URL the federated credentials trust (modules/azure/aks output oidc\_issuer\_url). | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the identity lands in (created by the composition). | `string` | n/a | yes |
| <a name="input_storage_account_id"></a> [storage\_account\_id](#input\_storage\_account\_id) | Scope of the Storage Blob Data Contributor grant: a storage account ID, or a container's resource manager ID to limit the grant to one container. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | Client id stamped on the app service account (azure.workload.identity/client-id annotation). Maps to the cross-cloud output contract 'runner\_identity'. |
| <a name="output_identity_id"></a> [identity\_id](#output\_identity\_id) | Resource ID of the user-assigned identity. |
| <a name="output_name"></a> [name](#output\_name) | Name of the user-assigned identity. |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | Principal (object) id of the identity, for role assignments. |
<!-- END_TF_DOCS -->
