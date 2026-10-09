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

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the cluster lands in | — |
| `location` | Azure region | — |
| `create_cluster` | provision (`true`) vs connect to existing (`false`) | `true` |
| `kubernetes_version` | version (create) | `null` (AKS default) |
| `vnet_id` / `network_role_enabled` | VNet for Network Contributor grant | `""` / `true` |
| `vnet_subnet_id` | node subnet (`vnet` output `subnet_aks_id`) | `""` |
| `sku_tier` | `Free` / `Standard` / `Premium` | `Standard` |
| `node_vm_size` | node pool VM size | `Standard_D4s_v6` |
| `node_min_count` / `node_max_count` | autoscaler bounds | `2` / `4` |
| `acr_id` | registry to grant kubelet AcrPull (empty skips) | `""` |

### Key outputs

| Name | Description |
|------|-------------|
| `cluster_name` | cluster name — maps to the contract `cluster_name` |
| `oidc_issuer_url` | OIDC issuer for workload-identity federation |
| `kubelet_identity_object_id` | kubelet identity (AcrPull) |
| `cluster_id`, `node_resource_group` | cluster ids |
| `host`, `cluster_ca_certificate` | kubeconnection (sensitive) |
<!-- END_TF_DOCS -->
