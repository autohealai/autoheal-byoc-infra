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

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the VMSS lands in | — |
| `location` | Azure region | — |
| `subnet_id` | runner subnet (`vnet` output `subnet_runner_id`) | — |
| `acr_id` / `acr_name` | registry to grant AcrPull / for `az acr login` | — |
| `temporal_host` | Temporal frontend `host:port` (internal LB) | — |
| `runner_image` / `sandbox_image` | fully-qualified images | — |
| `admin_ssh_public_key` | break-glass SSH key | — |
| `vm_sku` | VM size | `Standard_D4s_v6` |
| `instance_count` | runner count | `1` |
| `os_disk_size_gb` | OS disk size | `200` |

### Key outputs

| Name | Description |
|------|-------------|
| `vmss_id` | VMSS resource id |
| `identity_principal_id` / `identity_client_id` | runner identity ids |
<!-- END_TF_DOCS -->
