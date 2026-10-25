# Autoheal BYOC - Azure runner VMSS

VMSS that runs the runner-go worker as a container (Docker-out-of-Docker) in the
runner subnet, polling Temporal's `runners` namespace at `temporal_host`. The AWS
analogue is the EKS EC2/ASG runner. No public IP: egress is via the runner
subnet's NAT gateway (`compositions/azure-runner`). The user-assigned identity
can be granted AcrPull; when `acr_name` is set, cloud-init also installs the
Azure CLI and refreshes the ACR login hourly. runner-go pulls the sandbox image
through the Docker API, which does not use the host's login, so each refresh
also writes a login file in the form runner-go reads. With public images none
of this runs.

`compositions/azure-runner` creates it as its own step, after the app:
`temporal_host` is the chart's runner host on 443, reached through the edge
over TLS (`temporal_tls`) with the runner key (`temporal_token`), or the
private address of the chart's runner load balancers with TLS off. The runner
retries until Temporal answers. `temporal_ca_certificate` adds a private CA to
the trust store runner-go reads. The key sits in `/opt/runner-go/config.env`,
readable by root only, and runner-go's lambda drivers are off
(`DISABLED_DRIVERS`), since a lambda would run with that environment. Before
each start the systemd unit blocks containers, sandboxes included, from the
instance metadata service, so only the host uses the VM's identity, then pulls
`runner_image`
and retries with a backoff (15 seconds, doubling up to 5 minutes) until the
pull succeeds, so the image may be pushed to a new registry after the apply
without reimaging the VMs. `tool_response_callback_url` sets
`SANDBOX_TOOL_RESPONSE_CALLBACK_URL`; empty sends sandbox tool results through
Temporal. Naming and tags follow the repo's null-label convention (see
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
| [azurerm_linux_virtual_machine_scale_set.runner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine_scale_set) | resource |
| [azurerm_role_assignment.acr_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.runner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acr_id"></a> [acr\_id](#input\_acr\_id) | ACR resource ID to grant the runner identity AcrPull on. Used only when acr\_pull\_enabled is true. | `string` | `""` | no |
| <a name="input_acr_name"></a> [acr\_name](#input\_acr\_name) | ACR name for `az acr login -n` in the credential-refresh timer. Empty means the images are public: no Azure CLI is installed and no login runs. | `string` | `""` | no |
| <a name="input_acr_pull_enabled"></a> [acr\_pull\_enabled](#input\_acr\_pull\_enabled) | Grant the runner identity AcrPull on acr\_id. Plan-time bool: acr\_id is computed when the ACR is created in the same apply, so it cannot gate count. Leave false when images come from a public registry. | `bool` | `false` | no |
| <a name="input_admin_ssh_public_key"></a> [admin\_ssh\_public\_key](#input\_admin\_ssh\_public\_key) | SSH public key for the admin user (break-glass; the SSM-equivalent is az run-command). No password auth. | `string` | n/a | yes |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Admin username on the VMSS instances. | `string` | `"azureuser"` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | VMSS instance count. Each runner is an independent Temporal worker; scale out by raising this. | `number` | `1` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_max_concurrent_activities"></a> [max\_concurrent\_activities](#input\_max\_concurrent\_activities) | API\_WORKER\_MAX\_CONCURRENT\_ACTIVITIES per runner. 20 matches Autoheal's hosted runners on the same 4 vCPU, 16 GiB size. | `number` | `20` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_os_disk_size_gb"></a> [os\_disk\_size\_gb](#input\_os\_disk\_size\_gb) | OS disk size in GiB. Holds Docker layers, sandbox dirs and git datasource caches. Premium SSD speed grows with size: 1024 GiB is P30 (5000 IOPS, 200 MB/s), the smallest size at least as fast as the 3000 IOPS gp3 disk of Autoheal's hosted runners. 200 GiB (P15, 1100 IOPS) left the first chat after a boot waiting minutes on disk writes. | `number` | `1024` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the VMSS lands in (created by the composition). | `string` | n/a | yes |
| <a name="input_runner_image"></a> [runner\_image](#input\_runner\_image) | Fully qualified runner-go image, e.g. public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0. | `string` | n/a | yes |
| <a name="input_runner_name"></a> [runner\_name](#input\_runner\_name) | NAME env the worker registers under. | `string` | `"runner-byoc-aks"` | no |
| <a name="input_sandbox_image"></a> [sandbox\_image](#input\_sandbox\_image) | Fully qualified sandbox image to pre-pull on boot. Empty skips the pre-pull. | `string` | `""` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Runner subnet id (snet-runner from compositions/azure-runner, or the customer's). Egress is via that subnet's NAT gateway; the VMSS gets no public IP. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_temporal_ca_certificate"></a> [temporal\_ca\_certificate](#input\_temporal\_ca\_certificate) | PEM of the CA that signed the Temporal certificate, when the system trust store does not have it, such as a private CA on the edge. The runner trusts it in addition to the system CAs. Empty adds none. | `string` | `""` | no |
| <a name="input_temporal_host"></a> [temporal\_host](#input\_temporal\_host) | Temporal frontend host:port the runner polls, set as TEMPORAL\_HOST: the chart's runner host on 443, e.g. runner.autoheal.acme.example:443, or the private address of a Temporal load balancer on 7233. | `string` | n/a | yes |
| <a name="input_temporal_server_name"></a> [temporal\_server\_name](#input\_temporal\_server\_name) | Name the runner checks in the Temporal certificate (TEMPORAL\_SERVER\_NAME). Empty means the host of temporal\_host. | `string` | `""` | no |
| <a name="input_temporal_tls"></a> [temporal\_tls](#input\_temporal\_tls) | Dial Temporal over TLS (TEMPORAL\_TLS). True for the chart's runner host; false only for a Temporal load balancer on a private route. | `bool` | `true` | no |
| <a name="input_temporal_token"></a> [temporal\_token](#input\_temporal\_token) | Key the runner sends with each Temporal call (TEMPORAL\_TOKEN): the vault entry runner-token that the chart's proxy checks on the runner host. Written to a root-only file on the VMs. Empty sends none. | `string` | `""` | no |
| <a name="input_tool_response_callback_url"></a> [tool\_response\_callback\_url](#input\_tool\_response\_callback\_url) | URL the runner posts sandbox tool results to, set as SANDBOX\_TOOL\_RESPONSE\_CALLBACK\_URL: the api-server-go internal listener, e.g. http://10.60.15.253:8083/api/v1/internal/sandbox-tool-responses. Empty leaves it unset and tool results go through Temporal only. | `string` | `""` | no |
| <a name="input_upgrade_mode"></a> [upgrade\_mode](#input\_upgrade\_mode) | VMSS upgrade mode. With Manual, an apply that changes the model (such as a new runner image tag) updates and reimages each instance, through the azurerm features roll\_instances\_when\_required and reimage\_on\_manual\_upgrade (both on by default). Automatic makes the provider start a rolling OS upgrade, which needs a health probe this module does not set, so such an apply fails. | `string` | `"Manual"` | no |
| <a name="input_vm_sku"></a> [vm\_sku](#input\_vm\_sku) | VM size. Some policies forbid Intel Dsv5; D4s\_v6 is validated. | `string` | `"Standard_D4s_v6"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_identity_client_id"></a> [identity\_client\_id](#output\_identity\_client\_id) | Client id of the runner's user-assigned identity. |
| <a name="output_identity_name"></a> [identity\_name](#output\_identity\_name) | Name of the runner's user-assigned identity. |
| <a name="output_identity_principal_id"></a> [identity\_principal\_id](#output\_identity\_principal\_id) | Principal id of the runner's user-assigned identity (granted AcrPull when acr\_pull\_enabled). |
| <a name="output_vmss_id"></a> [vmss\_id](#output\_vmss\_id) | Resource ID of the runner VMSS. |
<!-- END_TF_DOCS -->
