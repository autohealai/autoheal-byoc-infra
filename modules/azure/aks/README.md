# Autoheal BYOC — Azure Kubernetes Service

AKS cluster for a BYOC install, with a user-assigned control-plane identity
(Network Contributor on the custom VNet), OIDC issuer + workload identity enabled,
Azure CNI overlay + Cilium, and an autoscaling default node pool. The kubelet
identity is granted AcrPull on the customer registry. Supports **create** mode
(provision) and **connect** mode (read an existing cluster), like `modules/aws/eks`.

Clusters are the one place the repo may wrap a pinned upstream AVM module instead
of raw resources; that choice is deferred per-cluster. This is a faithful own-model
port so the output contract is stable either way. Naming and tags follow the repo's
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
| [azurerm_kubernetes_cluster.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_role_assignment.acr_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.cluster_network](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_kubernetes_cluster.existing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/kubernetes_cluster) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acr_id"></a> [acr\_id](#input\_acr\_id) | ACR resource id to grant the kubelet identity AcrPull on. Empty skips (e.g. pull-through or public registry). | `string` | `""` | no |
| <a name="input_acr_pull_enabled"></a> [acr\_pull\_enabled](#input\_acr\_pull\_enabled) | Grant the kubelet identity AcrPull on var.acr\_id. Plan-time bool: acr\_id is usually a computed ACR id (module.acr.acr\_id), which cannot gate count directly — so a composition that creates its ACR must gate on this instead. Set false (with acr\_id empty) for pull-through / public-registry clusters. | `bool` | `true` | no |
| <a name="input_admin_group_object_ids"></a> [admin\_group\_object\_ids](#input\_admin\_group\_object\_ids) | Entra (AAD) group object IDs granted cluster-admin via managed-AAD + Azure RBAC. Empty = Kubernetes RBAC only (no managed-AAD integration). Deployment-specific, so there is no default. | `list(string)` | `[]` | no |
| <a name="input_api_server_authorized_ip_ranges"></a> [api\_server\_authorized\_ip\_ranges](#input\_api\_server\_authorized\_ip\_ranges) | CIDRs allowed to reach the public AKS API server. Empty = no IP restriction; set your admin/CI egress CIDRs for production. Ignored when private\_cluster\_enabled = true (a private cluster has no public endpoint). | `list(string)` | `[]` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Extra qualifiers appended to id, e.g. ['db']. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_create_cluster"></a> [create\_cluster](#input\_create\_cluster) | true (default) provisions the cluster; false connects to an existing cluster (same label id) in var.resource\_group\_name and creates no cluster resources (the AWS eks module's create\_cluster analogue). | `bool` | `true` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Lifecycle (stage/prod/play) in this repo — NOT region. | `string` | `null` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version (create mode). null = AKS default. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | Order of ID elements in id. Repo default drops 'stage'. | `list(string)` | <pre>[<br/>  "namespace",<br/>  "environment",<br/>  "name",<br/>  "attributes"<br/>]</pre> | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ID element. Component name, e.g. 'autoheal'. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Customer/tenant, e.g. 'avid'. | `string` | `null` | no |
| <a name="input_network_role_enabled"></a> [network\_role\_enabled](#input\_network\_role\_enabled) | Grant the control-plane UAMI Network Contributor on var.vnet\_id (create mode, custom VNet). Must be a plan-time bool: vnet\_id is a computed id, so it cannot gate count directly. Set false only for an AKS-managed VNet. | `bool` | `true` | no |
| <a name="input_node_max_count"></a> [node\_max\_count](#input\_node\_max\_count) | Default node pool autoscaler maximum. | `number` | `4` | no |
| <a name="input_node_min_count"></a> [node\_min\_count](#input\_node\_min\_count) | Default node pool autoscaler minimum. | `number` | `2` | no |
| <a name="input_node_vm_size"></a> [node\_vm\_size](#input\_node\_vm\_size) | Default node pool VM size. Some policies forbid Intel Dsv5; D4s\_v6 is the validated SKU. | `string` | `"Standard_D4s_v6"` | no |
| <a name="input_private_cluster_enabled"></a> [private\_cluster\_enabled](#input\_private\_cluster\_enabled) | Provision a private control plane: the API server is reachable only from the VNet and peered/connected networks, with no public endpoint. Default false = public endpoint (restrict it with api\_server\_authorized\_ip\_ranges). Whatever runs kubectl/Terraform must have in-VNet connectivity when true. | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the cluster lands in (created by the composition). | `string` | n/a | yes |
| <a name="input_sku_tier"></a> [sku\_tier](#input\_sku\_tier) | AKS SKU tier: Free \| Standard \| Premium. | `string` | `"Standard"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags, merged into the generated tag set. | `map(string)` | `{}` | no |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Entra tenant for managed-AAD RBAC. Empty = the current provider's tenant. Only used when admin\_group\_object\_ids is set. | `string` | `""` | no |
| <a name="input_vnet_id"></a> [vnet\_id](#input\_vnet\_id) | VNet id the control-plane UAMI gets Network Contributor on (create mode, custom VNet). | `string` | `""` | no |
| <a name="input_vnet_subnet_id"></a> [vnet\_subnet\_id](#input\_vnet\_subnet\_id) | Subnet id for the default node pool (create mode); modules/azure/vnet output subnet\_aks\_id. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Cluster CA certificate (base64). |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | Resource ID of the cluster. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | AKS cluster name. Maps to the cross-cloud output contract 'cluster\_name'. |
| <a name="output_host"></a> [host](#output\_host) | Kubernetes API server host. |
| <a name="output_kubelet_identity_object_id"></a> [kubelet\_identity\_object\_id](#output\_kubelet\_identity\_object\_id) | Kubelet identity object id (granted AcrPull for node image pulls). |
| <a name="output_node_resource_group"></a> [node\_resource\_group](#output\_node\_resource\_group) | Auto-managed node resource group (MC\_*). |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | OIDC issuer URL for Entra Workload Identity federated credentials (feeds modules/azure/workload-identity). |
<!-- END_TF_DOCS -->
