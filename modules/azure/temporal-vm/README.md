# Autoheal BYOC - Azure Temporal VM

One VM that runs the Temporal server for an install whose cluster cannot host
it. The app and the runner reach it over the internet on TCP 7233. Temporal
listens on 127.0.0.1 only. In front of it a gate (Envoy) ends TLS 1.3 and
checks a key on each call. Clients send `authorization: Bearer <key>`, and the
gate removes the header before the call goes on. Its routes, in order:

1. `/grpc.health.v1.Health/` with any valid key.
2. The runner key: the WorkflowService calls in `runner_allowed_methods`.
3. Every key: 401 on RegisterNamespace, UpdateNamespace, DeprecateNamespace,
   StartBatchOperation, DeleteWorkflowExecution, DeleteWorkerDeployment and
   DeleteWorkerDeploymentVersion.
4. The app keys (api-server and agents-py): the rest of WorkflowService.
5. Anything else: 401, which gRPC clients report as Unauthenticated.

OperatorService stays closed even with a key, and the routes match any host
name. The default `runner_allowed_methods` is what runner-go and the Temporal
Go SDK worker call. The access log records each call's path and the key's
entry and Key Vault version, never the key, so the list can be checked
against real traffic.

The keys and the certificate live in Key Vault, not in the custom data. A
timer (`temporal-secrets`) reads them at boot and every 5 minutes with the
VM's identity. For each key entry it takes the two newest enabled versions, so
a client can move to a new version before the old one is disabled. The
certificate entry is one secret with the certificate, its chain and the
private key, as PEM (`application/x-pem-file`) or base64 PKCS#12
(`application/x-pkcs12`); the secret behind a Key Vault certificate has this
form. The gate reloads a changed file and keeps open connections. When a
refresh fails, the gate keeps the last good keys and certificate.

The VM is the only instance of a scale set behind a Standard public load
balancer with one static IP. The load balancer forwards TCP 7233 and gives
the VM its way out on the same IP (an outbound rule), so Postgres, Key Vault
and the clients' firewalls see one address. The VM has no public IP of its
own and a VNet that is connected to nothing. The NSG lets in TCP 7233 from
`allowed_source_cidrs` and the load balancer (`AzureLoadBalancer`) on 7233
and `health_port`, and denies the rest, SSH included. Password login is off;
`az vmss run-command` reaches the host. Temporal keeps its data in Postgres
(the `temporal` and `temporal_visibility` databases), so the VM holds no
state. It connects with `sslmode` `verify-full`: the server's name and chain
are checked against the CAs in the images, which hold the roots Azure
Postgres chains to.

The load balancer probes the gate's health listener (`health_port`,
`/healthz`). It answers 200 only while the gate's own gRPC health check on
Temporal passes. While Temporal is off the probe fails and the load balancer
sends no new connections to the VM, so checks before the cutover run on the
VM itself.

The scale set has exactly one instance, upgrade mode Manual and no
overprovisioning, so Azure never runs two of these VMs at once. Two Temporal
servers on one database corrupt it. A change to the custom data (an image,
`runner_allowed_methods`, `start_temporal`, the database password) updates
the scale set model only. It reaches the VM when the operator runs
`az vmss update-instances` and then `az vmss reimage`, which works in place.
Set the provider feature `virtual_machine_scale_set { roll_instances_when_required = false }`
so an apply never does this on its own; compositions/azure-temporal sets it.
A new key or certificate version needs neither: the timer picks it up.

cloud-init installs Docker and these systemd units, each a container on the
host network:

- `temporal-edge` runs the gate and is always on. It starts once
  `temporal-secrets` has written its certificate and routes files.
- `temporal-secrets.timer` refreshes the keys and the certificate.
- `temporal-server` runs Temporal. Before the start it runs a guard, the
  schema step and the guard again. The guard (`scripts/temporal-guard.sh`)
  reads `cluster_membership` and fails while any member wrote a heartbeat in
  the last 60 seconds: another Temporal server uses the database. The unit
  then retries every 10 seconds. It is enabled at boot only when
  `start_temporal` is true.
- `temporal-namespaces` creates the `agents`, `runners` and `notifications`
  namespaces (3-day retention) after each start.

Each unit pulls its image and retries with a backoff until the pull succeeds.
The database password is in the custom data, which Azure never returns on
read, and in a root-only file.

`start_temporal` defaults to false: the gate runs and Temporal stays off. At
the cutover, once the cluster's Temporal has stopped, the operator starts it
on the VM (the instance ID comes from `az vmss list-instances`):

```sh
az vmss run-command invoke -g <resource group> -n <vmss_name> --instance-id <id> \
  --command-id RunShellScript \
  --scripts "systemctl enable --now temporal-server.service temporal-namespaces.service"
```

Then set `start_temporal = true` and apply. That changes only the scale set
model, so a later reimage starts Temporal at boot. It also turns on the
health alert.

With `log_analytics_workspace_id` set, the module adds the Azure Monitor
agent (signed in with the VM's identity) and a data collection rule that
sends the daemon syslog facility to the workspace. The units log to the
journal as `temporal-edge`, `temporal-secrets` and `temporal-server`, and
journald passes the lines on to syslog. The health alert fires when the load
balancer's probe (DipAvailability) has stayed below 100 for 5 minutes and
notifies `action_group_ids`; it exists with or without a workspace. With a
workspace, a log alert also notifies them while the key refresh warns that
the gate's certificate expires within 30 days or has expired; it checks
hourly and resolves itself once a new certificate is in place. Naming
and tags follow the repo's null-label convention (see `label.tf` and
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
| [azurerm_lb.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb) | resource |
| [azurerm_lb_backend_address_pool.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_backend_address_pool) | resource |
| [azurerm_lb_outbound_rule.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_outbound_rule) | resource |
| [azurerm_lb_probe.health](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_probe) | resource |
| [azurerm_lb_rule.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_rule) | resource |
| [azurerm_linux_virtual_machine_scale_set.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine_scale_set) | resource |
| [azurerm_monitor_data_collection_rule.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |
| [azurerm_monitor_data_collection_rule_association.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule_association) | resource |
| [azurerm_monitor_metric_alert.health](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.certificate](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_network_security_group.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_public_ip.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_subnet.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_user_assigned_identity.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_virtual_network.temporal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_action_group_ids"></a> [action\_group\_ids](#input\_action\_group\_ids) | Resource IDs of action groups the health alert and the certificate alert notify. Empty means the alerts show only in the portal. | `list(string)` | `[]` | no |
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | Address range of the VNet, all of it for the subnet snet-temporal. The VNet is connected to nothing, so any private range works. | `string` | n/a | yes |
| <a name="input_admin_ssh_public_key"></a> [admin\_ssh\_public\_key](#input\_admin\_ssh\_public\_key) | SSH public key for the admin user. No password login. The NSG lets no SSH in; use az vmss run-command to reach the host. | `string` | n/a | yes |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Admin username on the VM. | `string` | `"azureuser"` | no |
| <a name="input_agents_key_secret_name"></a> [agents\_key\_secret\_name](#input\_agents\_key\_secret\_name) | Key Vault entry with the agents-py key. The gate accepts its two newest enabled versions for the app routes. | `string` | `"temporal-agents-key"` | no |
| <a name="input_allowed_source_cidrs"></a> [allowed\_source\_cidrs](#input\_allowed\_source\_cidrs) | Public ranges allowed to reach the gate on TCP 7233, such as the cluster's outbound addresses and the runner's NAT IP. Nothing else gets in: no SSH, no other port. The load balancer keeps the client's address, so the NSG sees it. The VM's own IP is left out, so a list copied from the install's workload\_egress\_ip\_ranges works. | `list(string)` | n/a | yes |
| <a name="input_api_server_key_secret_name"></a> [api\_server\_key\_secret\_name](#input\_api\_server\_key\_secret\_name) | Key Vault entry with the api-server-go key. The gate accepts its two newest enabled versions for the app routes. | `string` | `"temporal-api-server-key"` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_certificate_secret_name"></a> [certificate\_secret\_name](#input\_certificate\_secret\_name) | Key Vault secret with the gate's certificate, its chain and its private key: the name of a Key Vault certificate (its secret has the same name), or a secret with content type application/x-pem-file. PEM and PKCS#12 (application/x-pkcs12) both work. The gate serves its newest version. | `string` | n/a | yes |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_health_port"></a> [health\_port](#input\_health\_port) | Port of the plain HTTP health listener the load balancer probes at /healthz. Only the AzureLoadBalancer tag may reach it. Not 7233-7235 or 6933-6939, which Temporal and the gate use. | `number` | `8080` | no |
| <a name="input_key_vault_uri"></a> [key\_vault\_uri](#input\_key\_vault\_uri) | URI of the Key Vault that holds the keys and the certificate, e.g. https://acme-prod-autoheal.vault.azure.net/. The VM reads it with its identity, which needs Key Vault Secrets User on each entry below, and from its public IP, which the vault firewall must let in. | `string` | n/a | yes |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Resource ID of a Log Analytics workspace. When set, the VM gets the Azure Monitor agent (signed in with its identity) and a data collection rule that sends the daemon syslog facility, which carries the journal of the gate, the key refresh and Temporal, to the workspace. Empty sends nothing. | `string` | `""` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'acme'. | `string` | `null` | no |
| <a name="input_num_history_shards"></a> [num\_history\_shards](#input\_num\_history\_shards) | numHistoryShards of the Temporal config. It must match the value the database was set up with and can never change after that. | `number` | `512` | no |
| <a name="input_os_disk_size_gb"></a> [os\_disk\_size\_gb](#input\_os\_disk\_size\_gb) | OS disk size in GiB. Temporal keeps its data in Postgres; the disk holds the OS and three images. | `number` | `64` | no |
| <a name="input_postgres_fqdn"></a> [postgres\_fqdn](#input\_postgres\_fqdn) | Host name of the Postgres server with the temporal and temporal\_visibility databases, e.g. acme-prod-autoheal-db.postgres.database.azure.com. | `string` | n/a | yes |
| <a name="input_proxy_image"></a> [proxy\_image](#input\_proxy\_image) | Fully qualified Envoy image for the gate on 7233, e.g. public.ecr.aws/e4h3h0d9/external/envoy:distroless-v1.35.6. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the VM and its network land in (created by the composition). | `string` | n/a | yes |
| <a name="input_runner_allowed_methods"></a> [runner\_allowed\_methods](#input\_runner\_allowed\_methods) | WorkflowService methods the runner key may call, by name. Anything else is 401 for the runner key. Null means the default list. | `list(string)` | <pre>[<br/>  "GetSystemInfo",<br/>  "DescribeNamespace",<br/>  "PollWorkflowTaskQueue",<br/>  "PollActivityTaskQueue",<br/>  "RespondWorkflowTaskCompleted",<br/>  "RespondWorkflowTaskFailed",<br/>  "RespondQueryTaskCompleted",<br/>  "RespondActivityTaskCompleted",<br/>  "RespondActivityTaskFailed",<br/>  "RespondActivityTaskCanceled",<br/>  "RecordActivityTaskHeartbeat",<br/>  "GetWorkflowExecutionHistory",<br/>  "ShutdownWorker",<br/>  "SetWorkerDeploymentCurrentVersion"<br/>]</pre> | no |
| <a name="input_runner_key_secret_name"></a> [runner\_key\_secret\_name](#input\_runner\_key\_secret\_name) | Key Vault entry with the runner key. The gate accepts its two newest enabled versions for the runner route only. | `string` | `"runner-token"` | no |
| <a name="input_start_temporal"></a> [start\_temporal](#input\_start\_temporal) | Start the Temporal server when the VM is built. False installs it but leaves it off, and only the gate runs. The scale set uses upgrade mode Manual, so a change reaches the VM only when it is reimaged; at cutover the operator starts Temporal with run-command and then sets this to true. Also turns the health alert on. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_temporal_admin_tools_image"></a> [temporal\_admin\_tools\_image](#input\_temporal\_admin\_tools\_image) | Fully qualified Temporal admin-tools image, for the schema and namespace steps. | `string` | n/a | yes |
| <a name="input_temporal_db_password"></a> [temporal\_db\_password](#input\_temporal\_db\_password) | Password of temporal\_user. Written to a root-only file on the VM. | `string` | n/a | yes |
| <a name="input_temporal_server_image"></a> [temporal\_server\_image](#input\_temporal\_server\_image) | Fully qualified Temporal server image, e.g. public.ecr.aws/e4h3h0d9/external/temporal-server:1.29.0. | `string` | n/a | yes |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | VM size. It must support accelerated networking and Premium SSD. 2 vCPU and 8 GiB carry one Temporal server for one install. | `string` | `"Standard_D2s_v6"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_certificate_alert_id"></a> [certificate\_alert\_id](#output\_certificate\_alert\_id) | Resource ID of the log alert on the gate's certificate expiry. Null without log\_analytics\_workspace\_id. |
| <a name="output_data_collection_rule_id"></a> [data\_collection\_rule\_id](#output\_data\_collection\_rule\_id) | Resource ID of the data collection rule that sends the VM's logs to the workspace. Null without log\_analytics\_workspace\_id. |
| <a name="output_health_alert_id"></a> [health\_alert\_id](#output\_health\_alert\_id) | Resource ID of the metric alert on the load balancer's health probe. |
| <a name="output_identity_client_id"></a> [identity\_client\_id](#output\_identity\_client\_id) | Client ID of the VM's user-assigned identity. |
| <a name="output_identity_id"></a> [identity\_id](#output\_identity\_id) | Resource ID of the VM's user-assigned identity. |
| <a name="output_identity_principal_id"></a> [identity\_principal\_id](#output\_identity\_principal\_id) | Principal ID of the VM's user-assigned identity. Grant it Key Vault Secrets User on each key entry and the certificate entry. |
| <a name="output_load_balancer_id"></a> [load\_balancer\_id](#output\_load\_balancer\_id) | Resource ID of the load balancer in front of the VM. |
| <a name="output_network_security_group_id"></a> [network\_security\_group\_id](#output\_network\_security\_group\_id) | Resource ID of the NSG on snet-temporal. |
| <a name="output_public_ip"></a> [public\_ip](#output\_public\_ip) | Static public IP of the load balancer. Clients dial <public\_ip>:7233, and the VM's outbound traffic leaves from it. |
| <a name="output_vmss_id"></a> [vmss\_id](#output\_vmss\_id) | Resource ID of the Temporal scale set (one VM). |
| <a name="output_vmss_name"></a> [vmss\_name](#output\_vmss\_name) | Name of the Temporal scale set, for az vmss run-command and az vmss reimage. |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | Resource ID of the VM's VNet. |
<!-- END_TF_DOCS -->
