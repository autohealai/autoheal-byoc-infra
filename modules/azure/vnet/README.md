# Autoheal BYOC — Azure VNet

Network substrate for a BYOC-on-AKS Autoheal install. Creates a VNet with five
purpose-built subnets (AKS nodes, PG-delegated, private endpoints, Redis VNet
injection, runner VMSS), a NAT gateway for runner egress, the PostgreSQL Flexible
Server private DNS zone, and optional privatelink DNS zones for Blob, Key Vault,
and AI Foundry / Azure OpenAI.

The AWS analogue is `modules/aws/vpc`. Naming and tags follow the repo's
null-label convention (see `context.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     The module-specific inputs are in variables.tf; label inputs (namespace,
     environment, name, attributes, tags, ...) come from context.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the network lands in (created by the composition) | — |
| `location` | Azure region | — |
| `address_space` | VNet address space | `["10.60.0.0/16"]` |
| `runner_nat_enabled` | NAT gateway for runner-subnet egress | `true` |
| `pg_private_dns_zone_name` | PG Flexible private DNS zone (empty = none) | `""` |
| `private_endpoints_enabled` | privatelink zones for Blob + Key Vault | `false` |
| `foundry_private_endpoint_enabled` | privatelink zones for AI Foundry / Azure OpenAI | `false` |

### Key outputs

| Name | Description |
|------|-------------|
| `vnet_id`, `vnet_name` | the VNet |
| `subnet_{aks,db,pe,redis,runner}_id` | subnet IDs by role |
| `runner_nat_public_ip` | static egress IP for allowlisting |
| `pg_private_dns_zone_id` | PG private DNS zone |
| `blob_private_dns_zone_id`, `vault_private_dns_zone_id`, `foundry_private_dns_zone_ids` | privatelink zones when enabled |
<!-- END_TF_DOCS -->
