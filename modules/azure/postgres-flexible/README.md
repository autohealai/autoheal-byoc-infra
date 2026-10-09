# Autoheal BYOC — Azure PostgreSQL Flexible Server

Provisioned, private (VNet-integrated) PostgreSQL Flexible Server for a
BYOC-on-AKS Autoheal install. No public endpoint: it attaches to the PG-delegated
subnet and the private DNS zone created by `modules/azure/vnet`, so it is
reachable only from inside the VNet (AKS pods).

Sets the `azure.extensions` server configuration so `CREATE EXTENSION` (pgvector,
btree_gin, pg_trgm, ...) succeeds. Azure Flexible rejects any extension not
pre-listed, a gap RDS did not have.

The AWS analogue is `modules/aws/rds-cluster`. Naming and tags follow the repo's
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
| `resource_group_name` | RG the server lands in (created by the composition) | — |
| `location` | Azure region | — |
| `delegated_subnet_id` | PG-delegated subnet (`vnet` output `subnet_db_id`) | — |
| `private_dns_zone_id` | PG private DNS zone (`vnet` output `pg_private_dns_zone_id`) | — |
| `administrator_password` | admin password (composition-generated, sensitive) | — |
| `sku_name` | tier+size; BYOC policy = provisioned (`GP_`/`MO_`) | `GP_Standard_D2ds_v5` |
| `postgres_version` | major version | `16` |
| `storage_mb` | storage size (MB) | `32768` |
| `extensions` | `azure.extensions` allow-list (must precede CREATE EXTENSION) | `[VECTOR, BTREE_GIN, PG_TRGM, HSTORE, UUID-OSSP]` |

### Key outputs

| Name | Description |
|------|-------------|
| `host` | server FQDN — maps to the contract `postgres_host` |
| `port` | `5432` |
| `administrator_login` | admin username |
| `server_id`, `name` | server resource id / name |
<!-- END_TF_DOCS -->
