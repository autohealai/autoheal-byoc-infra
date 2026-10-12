# Autoheal BYOC — AWS ElastiCache for Redis

Node-based (provisioned) ElastiCache for Redis replication group for a BYOC-on-EKS
Autoheal install. `num_cache_clusters >= 2` gives a primary + replica with Multi-AZ
automatic failover (prod HA). Private: in the VPC private subnets, reachable only
from the security groups in `allowed_sg_ids` (the EKS node SG) on 6379; TLS in
transit and at-rest encryption on, access SG-restricted (no auth token by default).

The Azure analogue is `modules/azure/redis`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration wired to the `vpc`
module.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     Module-specific inputs are in variables.tf; label inputs come from label.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `vpc_id`, `vpc_cidr_block`, `subnet_ids` | placement (`vpc` outputs) | — |
| `allowed_sg_ids` | SGs allowed on 6379 (EKS node SG) | `[]` |
| `node_type` | cache node type | `cache.m7g.large` |
| `num_cache_clusters` | nodes (>= 2 = HA) | `2` |
| `engine_version` | Redis version | `7.1` |

### Key outputs

| Name | Description |
|------|-------------|
| `endpoint` | `primary:port` — maps to the contract `redis_endpoint` |
| `primary_endpoint_address`, `reader_endpoint_address`, `port` | endpoints / port |
| `security_group_id` | cache SG |
<!-- END_TF_DOCS -->
