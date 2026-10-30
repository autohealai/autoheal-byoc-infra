# Autoheal BYOC - Azure Temporal VM

One VM that runs the Temporal server for an install whose cluster cannot host
it. The app and the runner reach it over the internet on TCP 7233. Temporal
listens on 127.0.0.1 only; in front of it a proxy (Envoy) ends TLS 1.3 and
checks a key, as the chart's proxy guards the runner host. The app key opens
the worker API in every namespace. The runner key opens `GetSystemInfo`, which
the Go SDK calls first with no namespace header, and the worker API in the
`runners` namespace. Both open the gRPC health check. Any other call gets 401.
The namespace check reads the `temporal-namespace` header, which a stock SDK
sets, so it keeps a misconfigured runner out of the other namespaces. It is
not a hard boundary: a hand-made gRPC client with the runner key can send the
header and another namespace in the body, and Envoy cannot read the body. The
routes match any host name.

The VM has a static public IP and a VNet of its own that is connected to
nothing. The NSG lets in TCP 7233 from `allowed_source_cidrs` and denies the
rest, SSH included. Password login is off; the admin user has an SSH key
only, and `az vm run-command` reaches the host. Temporal keeps its data in
Postgres (the `temporal` and `temporal_visibility` databases), so the VM holds
no state.

cloud-init installs Docker and four systemd units, each a container on the
host network. `temporal-schema` sets up or upgrades the schema in both
databases and retries until Postgres answers. `temporal-server` runs Temporal
and is enabled only when `start_temporal` is true. `temporal-namespaces`
creates the `agents`, `runners` and `notifications` namespaces (3-day
retention) after each start. `temporal-edge` runs the proxy and is always on.
Each unit pulls its image and retries with a backoff until the pull succeeds.
The database password, the keys and the TLS key sit in root-only files (the
TLS key and the proxy config belong to the proxy's user, uid 65532).

Any change to the custom data replaces the VM: `start_temporal`, a key, the
certificate, an image or the database password. The public IP is a separate
resource and stays, so clients and firewall rules keep working. Moving from
`start_temporal = false` to `true` is a one-variable change that replaces the
VM with one that starts Temporal. Naming and tags follow the repo's null-label
convention (see `label.tf` and
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
| [azurerm_linux_virtual_machine.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_network_interface.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_network_security_group.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_public_ip.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_subnet.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_virtual_network.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | Address range of the VNet, all of it for the subnet snet-temporal. The VNet is connected to nothing, so any private range works. | `string` | n/a | yes |
| <a name="input_admin_ssh_public_key"></a> [admin\_ssh\_public\_key](#input\_admin\_ssh\_public\_key) | SSH public key for the admin user. No password login. The NSG lets no SSH in; use az vm run-command to reach the host. | `string` | n/a | yes |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Admin username on the VM. | `string` | `"azureuser"` | no |
| <a name="input_allowed_source_cidrs"></a> [allowed\_source\_cidrs](#input\_allowed\_source\_cidrs) | Public ranges allowed to reach the proxy on TCP 7233, such as the cluster's outbound addresses and the runner's NAT IP. Nothing else gets in: no SSH, no other port. | `list(string)` | n/a | yes |
| <a name="input_app_key"></a> [app\_key](#input\_app\_key) | Key the app sends as "Bearer <key>". It opens the worker API and the health check in every namespace. | `string` | n/a | yes |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_num_history_shards"></a> [num\_history\_shards](#input\_num\_history\_shards) | numHistoryShards of the Temporal config. It must match the value the database was set up with and can never change after that. | `number` | `512` | no |
| <a name="input_os_disk_size_gb"></a> [os\_disk\_size\_gb](#input\_os\_disk\_size\_gb) | OS disk size in GiB. Temporal keeps its data in Postgres; the disk holds the OS and three images. | `number` | `64` | no |
| <a name="input_postgres_fqdn"></a> [postgres\_fqdn](#input\_postgres\_fqdn) | Host name of the Postgres server with the temporal and temporal\_visibility databases, e.g. acme-prod-autoheal-db.postgres.database.azure.com. | `string` | n/a | yes |
| <a name="input_proxy_image"></a> [proxy\_image](#input\_proxy\_image) | Fully qualified Envoy image for the proxy on 7233, e.g. public.ecr.aws/e4h3h0d9/external/envoy:distroless-v1.35.6. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the VM and its network land in (created by the composition). | `string` | n/a | yes |
| <a name="input_runner_token"></a> [runner\_token](#input\_runner\_token) | Key the runner sends as "Bearer <key>". It opens GetSystemInfo, the worker API in the runners namespace, and the health check. | `string` | n/a | yes |
| <a name="input_start_temporal"></a> [start\_temporal](#input\_start\_temporal) | Start the Temporal server. False installs it but leaves it off, and only the proxy runs. Changing it changes the custom data, which replaces the VM; the static public IP stays. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_temporal_admin_tools_image"></a> [temporal\_admin\_tools\_image](#input\_temporal\_admin\_tools\_image) | Fully qualified Temporal admin-tools image, for the schema and namespace steps. | `string` | n/a | yes |
| <a name="input_temporal_db_password"></a> [temporal\_db\_password](#input\_temporal\_db\_password) | Password of temporal\_user. Written to a root-only file on the VM. | `string` | n/a | yes |
| <a name="input_temporal_server_image"></a> [temporal\_server\_image](#input\_temporal\_server\_image) | Fully qualified Temporal server image, e.g. public.ecr.aws/e4h3h0d9/external/temporal-server:1.29.0. | `string` | n/a | yes |
| <a name="input_tls_certificate"></a> [tls\_certificate](#input\_tls\_certificate) | PEM of the certificate the proxy serves on 7233. | `string` | n/a | yes |
| <a name="input_tls_private_key"></a> [tls\_private\_key](#input\_tls\_private\_key) | PEM of the private key of tls\_certificate. Written to a file only the proxy can read. | `string` | n/a | yes |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | VM size. It must support accelerated networking and Premium SSD. 2 vCPU and 8 GiB carry one Temporal server for one install. | `string` | `"Standard_D2s_v6"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_network_security_group_id"></a> [network\_security\_group\_id](#output\_network\_security\_group\_id) | Resource ID of the NSG on snet-temporal. |
| <a name="output_public_ip"></a> [public\_ip](#output\_public\_ip) | Static public IP of the VM. Clients dial <public\_ip>:7233; it stays when the VM is replaced. |
| <a name="output_vm_id"></a> [vm\_id](#output\_vm\_id) | Resource ID of the Temporal VM. |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | Name of the Temporal VM, for az vm run-command and az vm boot-diagnostics. |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | Resource ID of the VM's VNet. |
<!-- END_TF_DOCS -->
