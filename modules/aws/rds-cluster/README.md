# Autoheal BYOC — AWS Aurora PostgreSQL (provisioned)

Provisioned Aurora PostgreSQL cluster (writer + optional reader) for a BYOC-on-EKS
Autoheal install. BYOC policy is provisioned (e.g. `db.r7g.large`), never Serverless
v2 or burstable, for a real install. Private: reachable only from the security groups
in `allowed_sg_ids` (the EKS node SG) on 5432; storage encrypted.

The master password is generated and seeded into Secrets Manager by the composition
(this module takes it as a sensitive input, staying aws-only). The Azure analogue is
`modules/azure/postgres-flexible`. Naming and tags follow the repo's null-label
convention (see `label.tf` and
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
| `allowed_sg_ids` | SGs allowed on 5432 (EKS node SG) | `[]` |
| `master_password` | master password (composition-generated, sensitive) | — |
| `instance_class` | provisioned class (no `db.serverless`) | `db.r7g.large` |
| `engine_version` | Aurora PG version | `16.6` |
| `multi_az` | add a reader for HA | `true` |

### Key outputs

| Name | Description |
|------|-------------|
| `host` | writer endpoint — maps to the contract `postgres_host` |
| `reader_host`, `port` | reader endpoint / port |
| `security_group_id` | cluster SG |
| `cluster_id`, `cluster_arn` | cluster identifiers |
<!-- END_TF_DOCS -->
