# Autoheal BYOC — Azure Cache for Redis (Premium, VNet-injected)

Azure Cache for Redis, Premium SKU, injected directly into a dedicated subnet for a
BYOC-on-AKS Autoheal install. The cache gets a real IP in `modules/azure/vnet`'s
`snet-redis`, so AKS pods reach it privately with no Private Endpoint and no
privatelink DNS zone, and no public endpoint is exposed.

BYOC decision: Premium + VNet injection, **not** Managed/Enterprise Redis. VNet
injection is Premium-only and immutable after create — the subnet must be dedicated
and undelegated (`modules/azure/vnet` provisions `snet-redis` for exactly this).

The AWS analogue is `modules/aws/elasticache`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration wired to the
`vnet` module.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     The module-specific inputs are in variables.tf; label inputs (namespace,
     environment, name, attributes, tags, ...) come from label.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `resource_group_name` | RG the cache lands in (created by the composition) | — |
| `location` | Azure region | — |
| `subnet_id` | dedicated subnet to inject into (`vnet` output `subnet_redis_id`) | — |
| `capacity` | Premium size 1-5 (P1-P5) | `1` |
| `shard_count` | Redis Cluster shards (0 = off) | `0` |
| `redis_version` | Redis major version | `6` |
| `maxmemory_policy` | eviction policy | `volatile-lru` |
| `private_static_ip_address` | pin an IP in the injected subnet | `""` (auto) |

### Key outputs

| Name | Description |
|------|-------------|
| `endpoint` | `host:ssl_port` — maps to the contract `redis_endpoint` |
| `hostname`, `ssl_port` | cache host / TLS port |
| `primary_access_key` | access key (sensitive; seed into Key Vault) |
| `redis_id` | cache resource id |
<!-- END_TF_DOCS -->
