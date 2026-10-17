# compositions/azure

The Azure infrastructure for Autoheal, in one composition for every case: we
create everything, you bring everything, or a mix. Each building block takes an
optional `existing_*` ID. Leave it empty and we create the resource; set it and
we read the resource with a data source and never change it.

The composition does not install the chart. It outputs `autoheal_values` (the
chart's infra values) and `cluster` (how to reach the cluster), which
`compositions/app` takes as inputs. See `examples/azure` for a complete
deployment repository.

## Files

One file per building block.

| File | Creates, or reads when brought |
|------|--------------------------------|
| `network.tf` | Resource group, VNet with AKS, Postgres, private endpoint and runner subnets, the runner's NAT gateway, Postgres private DNS zone. Brought: `existing_resource_group_id`, `existing_network`. |
| `cluster.tf` | AKS with the OIDC issuer, workload identity, Entra ID RBAC and the Key Vault CSI driver add-on. Brought: `existing_aks_cluster_id`. |
| `postgres.tf` | PostgreSQL Flexible Server and its admin password. Brought: `existing_postgres_id`. |
| `redis.tf` | Azure Managed Redis. Brought: `existing_redis_id` (Managed Redis or Azure Cache for Redis). |
| `storage.tf` | Storage account and the blob container. Brought: `existing_storage_account_id`. |
| `keyvault.tf` | Key Vault (Azure RBAC). Brought: `existing_key_vault_id`. |
| `registry.tf` | Container registry, only with `create_registry = true`. Brought: `existing_acr_id`. |
| `identity.tf` | Workload identities, one per chart role, federated to the chart's service accounts. |
| `role-assignments.tf` | Grants, or the `required_role_assignments` list and the check that the grants exist. |
| `secrets.tf` | Every secret the chart reads, generated or passed in, written to the vault. |
| `private-endpoints.tf` | Private endpoints for the vault, storage and Redis, and the privatelink zones. |
| `dns.tf` | A records for the three hostnames in your existing zone. |
| `runner.tf` | runner-go on a VM scale set, connected to the reserved Temporal address. |
| `validation.tf` | Plan-time checks with plain messages. |
| `autoheal-values.tf` | The `autoheal_values` hand-off to the chart. |
| `moved.tf` | State moves from the v1 compositions. |

## Cases

| Case | Inputs |
|------|--------|
| 1. We create everything | `network_cidr`, `existing_dns_zone_id` (or `create_dns_records = false`) |
| 2a. You bring everything, our Terraform runs | `existing_network` and every `existing_*` ID, usually `create_role_assignments = false` |
| 3. Mixed | `existing_network` and `existing_dns_zone_id`; we create the rest |

Impossible mixes stop the plan with a message saying what to change, for example
a brought cluster without `existing_network`, a vault on access policies, a
storage account with hierarchical namespace, a Postgres server older than 15, a
reserved address outside the AKS subnet, or records with no zone.

## Reserved addresses

The runner VMs run outside the cluster and connect to Temporal at a fixed
internal address. In a network we create, the composition reserves the third and
second addresses from the end of the AKS subnet for Temporal and, in
`loadbalancer` mode, the proxy. In a brought network your network team picks
them (`existing_network.temporal_ip` and `proxy_ip`). They reach the chart as
`global.infra.temporal.internalIP` and `global.infra.edge.internalIP`, and the
DNS records point at the proxy address from the first apply.

## Edge modes

| `edge_mode` | DNS records point at | `global.infra.edge` |
|-------------|----------------------|---------------------|
| `loadbalancer` (default) | the reserved proxy address | `internalIP` |
| `gateway-api`, `istio`, `ingress` | `edge_address`; listed in `required_dns_records` while it is empty | not set |
| `none` | nothing; no records | not set |

## Role grants

With `create_role_assignments = true` (the default) Terraform makes every grant,
so the deployer needs Owner, or Contributor plus User Access Administrator. With
`false` it makes none: `required_role_assignments` lists each grant as a line an
administrator can act on, and the apply checks the workload grants and stops,
naming the missing ones, until they exist. On a first install the identities are
created in that apply, so expect the first run to stop at the check; make the
grants and run it again.

| Grant | When |
|-------|------|
| Key Vault Secrets User on the vault, for the secrets identity | Always |
| Storage Blob Data Contributor on the container, for the api-server and agents-worker identities | Always |
| Key Vault Secrets Officer on the vault, for the deployer | Vault we create. On a brought vault it is made when `create_role_assignments = true`, and not listed otherwise: the vault owner gives you write access. |
| Network Contributor on the VNet or AKS subnet, for the cluster identity | Cluster we create |
| Azure Kubernetes Service RBAC Cluster Admin on the cluster, for the deployer | Cluster we create |
| AcrPull on the registry, for the runner | With a registry |
| AcrPull on the registry, for the kubelet | With a registry and a cluster we create |

## Vault entries

Written in the same apply, to the vault we create or the one you bring. The chart
mounts them with the Key Vault CSI driver.

| Entry | Source |
|-------|--------|
| `postgres-admin-password` | Generated for a server we create; `postgres_admin_password` for a brought one |
| `api-server-db-password`, `agents-db-password`, `temporal-db-password`, `zitadel-db-password` | Generated |
| `api-server-database-url`, `agents-database-url` | Built from the host and the generated passwords |
| `api-server-jwt-secret`, `zitadel-master-key`, `auth-app-session-secret`, `first-admin-password` | Generated |
| `redis-access-key`, `api-server-redis-url` | Read from Redis, when there is one |
| `llm-api-key` | `llm_api_key`, when set |
| `sso-client-secret` | `sso_client_secret`, when set |
| `tls-certificate`, `tls-private-key` | `tls_certificate`, when set |
| `runner-ssh-private-key` | Generated when `runner_admin_ssh_public_key` is empty |

Generated values are kept across upgrades.

## Outputs

| Output | Contents |
|--------|----------|
| `autoheal_values` | The chart's infra values (below). Pass to `compositions/app` as `infra_values`. |
| `autoheal_values_yaml` | The same as YAML, for a Helm or Flux install. |
| `cluster` | `cloud`, `name`, `resource_group`, `endpoint`, base64 `ca_certificate`. No credential. |
| `required_role_assignments` | Grants for an administrator, filled when `create_role_assignments = false`. |
| `required_dns_records` | Records for a person to create (`name`, `type`, `value`), filled when we do not create them. |

`autoheal_values` keys:

```text
global.infra.version                          infra contract version, 2.0.0
global.infra.cloud                            azure
global.infra.hosts.{app,auth,authApp}
global.infra.keyVault.{name,tenantId}
global.infra.identities.{secrets,apiServer,agentsWorker}   client IDs
global.infra.database.{host,port,adminUser,adminPasswordVaultEntry}
global.infra.redis.{host,port}                when there is Redis
global.infra.objectStore.{kind,account,container}
global.infra.edge.internalIP                  loadbalancer mode only
global.infra.temporal.internalIP
global.addons.install                         suggestion: true when we created the cluster
global.secrets.mode                           suggestion: keyvault-csi
global.edge.mode                              suggestion: edge_mode
temporal.server.config.persistence.{default,visibility}.sql.host   copy of the database host
zitadel.zitadel.configmapConfig.ExternalDomain                     copy of hosts.auth
zitadel.zitadel.configmapConfig.Database.Postgres.Host             copy of the database host
```

None of the outputs holds a secret.

## Upgrading from 1.x

`moved.tf` moves both v1 compositions (`azure-byoc` and `azure-byoc-connect`)
into this one without replacing the cluster, the database, the storage account
or the vault, provided the inputs keep their v1 values. `CHANGELOG.md` lists the
inputs to set.

## Tests

```bash
terraform init -backend=false
terraform test
```

`tests/` plans each case against mocked providers: `create.tftest.hcl` (case 1
and each edge mode), `bring.tftest.hcl` (case 2a), `hybrid.tftest.hcl` (case 3)
and `reachability.tftest.hcl` (network paths to storage and the vault). They pass
on Terraform 1.9 and OpenTofu 1.11.
