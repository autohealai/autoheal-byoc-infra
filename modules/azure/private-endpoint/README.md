# Autoheal BYOC — Azure Private Endpoint

Generic private endpoint that projects a PaaS resource (Blob account, Key Vault,
AI Foundry account) into the private-endpoint subnet and registers its private IP
in the supplied privatelink DNS zones, so AKS pods resolve the resource to its
private address. Instantiate once per target, using `attributes` for a distinct
name (`["blob"]` / `["vault"]` / `["foundry"]`).

The AWS analogue is a VPC interface endpoint. This module adds only the private
path; disabling a resource's public access is coordinated separately. Naming and
tags follow the repo's null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the endpoint lands in | — |
| `location` | Azure region | — |
| `subnet_id` | PE subnet (`vnet` output `subnet_pe_id`) | — |
| `target_resource_id` | PaaS resource to privatize | — |
| `subresource_names` | `["blob"]` / `["vault"]` / `["account"]` | — |
| `private_dns_zone_ids` | privatelink zones to register in | — |

### Key outputs

| Name | Description |
|------|-------------|
| `id` | private endpoint resource id |
| `private_ip_address` | private VNet IP on the PE NIC |
<!-- END_TF_DOCS -->
