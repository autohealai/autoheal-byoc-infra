# Autoheal BYOC - Key Vault secrets identity

Entra identity the Key Vault CSI driver uses to read this install's vault on
AKS. Creates a user-assigned identity, federates it to each chart
ServiceAccount that mounts the SecretProviderClass, and grants it Key Vault
Secrets User on exactly this install's vault. The grant can be left to an
administrator with `role_assignment_enabled = false`.

It creates no in-cluster objects. The chart builds the SecretProviderClass from
`global.infra.keyVault` and this module's `client_id`.

Renamed from `azure/external-secrets` in 2.0.0. Naming and tags follow the
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
| [azurerm_federated_identity_credential.sa](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.kv_secrets_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_key_vault_id"></a> [key\_vault\_id](#input\_key\_vault\_id) | Key Vault the identity may read (Key Vault Secrets User). | `string` | n/a | yes |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | OIDC issuer URL of the AKS cluster the federated credentials trust. Unused when service\_accounts is empty (the caller then federates the identity elsewhere). | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the identity lands in. | `string` | n/a | yes |
| <a name="input_role_assignment_enabled"></a> [role\_assignment\_enabled](#input\_role\_assignment\_enabled) | Grant the identity Key Vault Secrets User on key\_vault\_id. Set false when the deployer cannot grant roles; an administrator then makes the grant. | `bool` | `true` | no |
| <a name="input_service_accounts"></a> [service\_accounts](#input\_service\_accounts) | Kubernetes ServiceAccounts federated to this identity: every ServiceAccount whose pods mount the Key Vault SecretProviderClass. An identity holds at most 20 federated credentials. | <pre>list(object({<br/>    namespace       = string<br/>    service_account = string<br/>  }))</pre> | <pre>[<br/>  {<br/>    "namespace": "autoheal",<br/>    "service_account": "api-server-go"<br/>  }<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | Client ID of the identity. The chart puts it in the SecretProviderClass (global.infra.identities.secrets). |
| <a name="output_identity_id"></a> [identity\_id](#output\_identity\_id) | Resource ID of the user-assigned identity. |
| <a name="output_name"></a> [name](#output\_name) | Name of the user-assigned identity. |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | Principal (object) ID of the identity, for role assignments made outside this module. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Entra tenant ID of the identity. |
<!-- END_TF_DOCS -->
