# Autoheal BYOC — Azure runner VMSS

VMSS that runs the runner-go worker as a container (Docker-out-of-Docker) in the
runner subnet, polling Temporal's `runners` namespace via the internal LB. The AWS
analogue is the EKS EC2/ASG runner. No public IP: egress is via the runner subnet's
NAT gateway (`modules/azure/vnet`). A user-assigned identity granted only AcrPull
lets it pull images keyless; cloud-init wires the systemd units and an hourly ACR
credential refresh.

Deploy this as a separate step after the cluster + Temporal are up, because it
needs `temporal_host` (the internal LB IP). Naming and tags follow the repo's
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
| [azurerm_linux_virtual_machine_scale_set.runner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine_scale_set) | resource |
| [azurerm_role_assignment.acr_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.runner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acr_id"></a> [acr\_id](#input\_acr\_id) | ACR resource id to grant the runner identity AcrPull. | `string` | n/a | yes |
| <a name="input_acr_name"></a> [acr\_name](#input\_acr\_name) | ACR registry name (for `az acr login -n` in the credential-refresh timer). | `string` | n/a | yes |
| <a name="input_admin_ssh_public_key"></a> [admin\_ssh\_public\_key](#input\_admin\_ssh\_public\_key) | SSH public key for the admin user (break-glass; the SSM-equivalent is az run-command). No password auth. | `string` | n/a | yes |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Admin username on the VMSS instances. | `string` | `"azureuser"` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | VMSS instance count. Each runner is an independent Temporal worker; scale out by raising this. | `number` | `1` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_max_concurrent_activities"></a> [max\_concurrent\_activities](#input\_max\_concurrent\_activities) | API\_WORKER\_MAX\_CONCURRENT\_ACTIVITIES per runner. | `number` | `5` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_os_disk_size_gb"></a> [os\_disk\_size\_gb](#input\_os\_disk\_size\_gb) | OS disk size. Holds Docker layers + sandbox dirs + git datasource caches; 30GB proved insufficient on the EC2 runner, so default large. | `number` | `200` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the VMSS lands in (created by the composition). | `string` | n/a | yes |
| <a name="input_runner_image"></a> [runner\_image](#input\_runner\_image) | Fully-qualified runner-go image, e.g. <acr>.azurecr.io/release/runner-go:<ver>. | `string` | n/a | yes |
| <a name="input_runner_name"></a> [runner\_name](#input\_runner\_name) | NAME env the worker registers under. | `string` | `"runner-byoc-aks"` | no |
| <a name="input_sandbox_image"></a> [sandbox\_image](#input\_sandbox\_image) | Fully-qualified sandbox image pre-pulled on boot, e.g. <acr>.azurecr.io/dev/sandbox:latest. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Runner subnet id (snet-runner from modules/azure/vnet). Egress is via that subnet's NAT gateway; the VMSS gets no public IP. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_temporal_host"></a> [temporal\_host](#input\_temporal\_host) | Temporal frontend as host:port, the internal LB (e.g. 10.60.0.7:7233). The runner polls the `runners` namespace here. | `string` | n/a | yes |
| <a name="input_vm_sku"></a> [vm\_sku](#input\_vm\_sku) | VM size. Some policies forbid Intel Dsv5; D4s\_v6 is validated. | `string` | `"Standard_D4s_v6"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_identity_client_id"></a> [identity\_client\_id](#output\_identity\_client\_id) | Client id of the runner's user-assigned identity. |
| <a name="output_identity_principal_id"></a> [identity\_principal\_id](#output\_identity\_principal\_id) | Principal id of the runner's user-assigned identity (granted AcrPull). |
| <a name="output_vmss_id"></a> [vmss\_id](#output\_vmss\_id) | Resource ID of the runner VMSS. |
<!-- END_TF_DOCS -->
