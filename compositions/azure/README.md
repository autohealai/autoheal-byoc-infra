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
| `network.tf` | Resource group, VNet with AKS, Postgres, private endpoint and runner subnets, the runner's NAT gateway, an NSG on the AKS subnet for the Temporal address, Postgres private DNS zone. Brought: `existing_resource_group_id`, `existing_network`. |
| `cluster.tf` | AKS with the OIDC issuer, workload identity, Entra ID RBAC and the Key Vault CSI driver add-on. Brought: `existing_aks_cluster_id`. |
| `postgres.tf` | PostgreSQL Flexible Server and its admin password. Brought: `existing_postgres_id`. |
| `redis.tf` | Azure Managed Redis. Brought: `existing_redis_id` (Managed Redis or Azure Cache for Redis). |
| `storage.tf` | Storage account and the blob container. Brought: `existing_storage_account_id`. |
| `keyvault.tf` | The install vault and the runtime vault, both Azure RBAC. Brought: `existing_key_vault_id`, `existing_runtime_key_vault_id`. |
| `registry.tf` | Container registry, only with `create_registry = true`. Brought: `existing_acr_id`. |
| `identity.tf` | Workload identities, one per chart role, federated to the chart's service accounts. The secrets identity is federated to `autoheal-hooks` only. |
| `role-assignments.tf` | Grants, or the `required_role_assignments` list and the check that the grants exist. |
| `secrets.tf` | Every secret the chart reads, generated or passed in, written to the vault. |
| `private-endpoints.tf` | Private endpoints for both vaults, storage and Redis, and the privatelink zones. |
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

The chart also puts the api-server-go internal listener on the Temporal
address, port 8083. The runners post sandbox tool results there
(`SANDBOX_TOOL_RESPONSE_CALLBACK_URL`, set by the composition). The listener
checks an HMAC key on each result, not the caller, so only the runner subnet
should reach it. In a network we create, an NSG on the AKS subnet allows ports
7233 and 8083 on the Temporal address from the runner subnet and denies them
from everywhere else. In a brought network, ask your network team for the same
rule.

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
| Key Vault Secrets User on the install vault, for the secrets identity | Always |
| Storage Blob Data Contributor on the storage account, for the api-server and agents-worker identities. A grant on one container is not enough: the Git Registry creates an `autoheal-<tenant-id>` container per tenant | Always |
| Key Vault Secrets Officer on the runtime vault, for the api-server identity | Always |
| Key Vault Secrets Officer on the install vault, for the deployer | Vault we create. On a brought vault it is made when `create_role_assignments = true`, and not listed otherwise: the vault owner gives you write access. |
| Network Contributor on the VNet or AKS subnet, for the cluster identity, which creates the internal load balancers on the reserved addresses | Cluster we create |
| Azure Kubernetes Service RBAC Cluster Admin on the cluster, for the deployer | Cluster we create |
| AcrPull on the registry, for the runner | With a registry |
| AcrPull on the registry, for the kubelet | With a registry. Made for a cluster we create. For a brought cluster it is listed and checked when `create_role_assignments = false`, and never made: the cluster owner usually has it already, and a duplicate grant fails the apply. |

## Vault entries

Written in the same apply, to the vault we create or the one you bring. The
names are the chart's defaults, the list in the chart's `docs/secrets.md`. The
chart's secrets-sync hook Job and CronJob, running as the `autoheal-hooks`
service account with the secrets identity, copy them into Kubernetes Secrets
through the Key Vault CSI driver. No service pod mounts the vault, so
`service_accounts.secrets` defaults to `["autoheal-hooks"]`.

| Entry | Source |
|-------|--------|
| `postgres-admin-password` | Generated for a server we create; `postgres_admin_password` for a brought one |
| `api-server-db-password`, `agents-db-password`, `temporal-db-password`, `zitadel-db-password` | Generated |
| `api-server-database-url` | Built from the host and the generated `app_user` password |
| `api-server-jwt-secret`, `zitadel-master-key`, `auth-app-session-secret`, `first-admin-password` | Generated |
| `oauth-encryption-key` | Generated: base64 of 32 random bytes, an AES-256 key for api-server-go |
| `oauth-state-signing-key` | Generated: base64 of 32 random bytes |
| `tool-response-server-secret` | Generated: 64 letters and digits |
| `redis-access-key`, `api-server-redis-url` | Read from Redis, when there is one. The URL is `rediss://:<key>@<host>:<port>/0`. |
| `llm-api-key` | `llm_api_key`, when set |
| `gateway-api-key` | `llm_gateway_api_key`, when set. The key of the customer's LLM gateway (`global.llm.gateway` in the chart). |
| `gateway-extra-headers` | `llm_gateway_extra_headers`, a JSON object of header strings, when set. `autoheal_values` then suggests `global.llm.gateway.extraHeadersVaultEntry`. |
| `sso-client-secret` | `sso_client_secret`, when set |
| `tls-certificate`, `tls-private-key` | `tls_certificate`, when set |
| `edge-ca-certificate` | `edge_ca_certificate`, when set. `autoheal_values` then suggests `global.edge.tls.caVaultEntry`. |
| `github-app-private-key` | `github_app_private_key` (PEM), stored base64-encoded, when set |
| `github-app-webhook-secret` | `github_app_webhook_secret`, when set |

Generated values are kept across upgrades. The chart reads the two GitHub
entries only when `values-customer.yaml` maps them in
`api-server-go.secretEnv` (`GITHUB_APP_PRIVATE_KEY_BASE64`,
`GITHUB_APP_WEBHOOK_SECRET`).

When `runner_admin_ssh_public_key` is empty we generate the runner SSH key. Its
private half is not written to the vault, which the secrets identity can read;
it stays in the Terraform state (`tls_private_key.runner`). Pass your own public
key to keep the private key out of the state.

## Runtime vault

api-server-go stores the integration credentials users enter in the product in
a second Key Vault, the runtime vault (`SECRET_MANAGER_PROVIDER=azurekeyvault`).
It is separate from the install vault so that the api-server identity, which
holds Key Vault Secrets Officer on the runtime vault, cannot read the install
secrets. api-server-go names its secrets `autoheal-rt-<sha256 hex>`, reads,
writes and deletes them, and recovers a soft-deleted one when a name is reused.
It never lists or purges.

The runtime vault we create is named `<namespace>-<environment>-autoheal-rt`
(cut to 24 characters), uses Azure RBAC, and has the same firewall, public
access setting and private endpoint as the install vault. Soft delete is on;
`runtime_key_vault_soft_delete_retention_days` defaults to 90 and
`runtime_key_vault_purge_protection_enabled` defaults to the install vault's
setting. To bring one, set `existing_runtime_key_vault_id`. It must use Azure
RBAC and must not be the install vault; the plan stops otherwise. The chart
reads it from `global.infra.runtimeSecrets`.

## Registry and images

With a registry (`create_registry = true` or `existing_acr_id`), `autoheal_values`
suggests `global.imageRegistry = <login server>` and the matching Temporal and
Zitadel image repositories, so the chart pulls every image from
`<login server>/app/<name>` and `<login server>/external/<name>`. Copy the
images there before you install the chart. The login server is
`<registry name>.azurecr.io`, so this assumes the Azure public cloud. With no
registry the chart pulls from `public.ecr.aws/e4h3h0d9`.

## Runner image

The runner VMs pull `runner_image_repository:runner_image_tag`. The repository
defaults to `<login server>/app/runner-go` with a registry and to
`public.ecr.aws/e4h3h0d9/app/runner-go` without one; the tag defaults to
`chart-<autoheal_version>`. They log in to the registry with their own identity
when the image is in it. runner-go uses the same login to pull the sandbox image
the first time a chat needs it; set `runner_sandbox_image` to pull it at boot
instead. They boot during
the apply and retry the pull with a backoff until it succeeds, so with a
registry created in the same apply you can push the image afterwards; the
runner starts within about five minutes of the push, with no reimage.

## Runner VMs

The runner VMs match Autoheal's hosted runners: 4 vCPU and 16 GiB
(`runner_vm_size`), 20 activities at once (`runner_max_concurrent_activities`)
and an OS disk of at least 3000 IOPS. Premium SSD speed grows with size, so
`runner_os_disk_size_gb` defaults to 1024 GiB (P30, 5000 IOPS). After a boot the
runner clones the data-source repos and unpacks the sandbox image; on a smaller
disk the first chat waits on those writes.

## Outputs

| Output | Contents |
|--------|----------|
| `autoheal_values` | The chart's infra values (below). Pass to `compositions/app` as `infra_values`. |
| `autoheal_values_yaml` | The same as YAML, for a Helm or Flux install. |
| `cluster` | `cloud`, `name`, `resource_group`, `endpoint`, base64 `ca_certificate`. No credential. |
| `required_role_assignments` | Grants for an administrator, filled when `create_role_assignments = false`. |
| `required_dns_records` | Records for a person to create (`name`, `type`, `value`), filled when we do not create them. |
| `network` | `vnet_id`, `vnet_name`, `resource_group_name`, `address_space`, `aks_subnet_id`, `runner_subnet_id`, `private_endpoint_subnet_id`. For a brought network the VNet is not read, so `address_space` is empty. |

`autoheal_values` keys:

```text
global.infra.version                          infra contract version, 2.0.0
global.infra.cloud                            azure
global.infra.hosts.{app,auth,authApp}
global.infra.keyVault.{name,tenantId}
global.infra.runtimeSecrets.{kind,vaultURL}   azurekeyvault, the runtime vault URI with a trailing slash
global.infra.identities.{secrets,apiServer,agentsWorker}   client IDs
global.infra.database.{host,port,adminUser,adminPasswordVaultEntry}
global.infra.redis.{host,port}                when there is Redis
global.infra.objectStore.{kind,account,container}
global.infra.edge.internalIP                  loadbalancer mode only
global.infra.temporal.internalIP
global.imageRegistry                          suggestion: the registry login server, with a registry
global.addons.install                         suggestion: true when we created the cluster
global.secrets.mode                           suggestion: keyvault-csi
global.edge.mode                              suggestion: edge_mode
global.edge.tls.caVaultEntry                  suggestion: edge-ca-certificate, when edge_ca_certificate is set
global.llm.gateway.extraHeadersVaultEntry     suggestion: gateway-extra-headers, when llm_gateway_extra_headers is set
temporal.server.config.persistence.{default,visibility}.sql.host   copy of the database host
zitadel.zitadel.configmapConfig.ExternalDomain                     copy of hosts.auth
zitadel.zitadel.configmapConfig.Database.Postgres.Host             copy of the database host
temporal.{server,web,admintools}.image.repository   copies of <login server>/external/<name>, with a registry
zitadel.image.repository, zitadel.login.image.repository   the same
zitadel.imageRegistry                                      copy of the login server, with a registry
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
and each edge mode), `bring.tftest.hcl` (case 2a), `hybrid.tftest.hcl` (case 3),
`reachability.tftest.hcl` (network paths to storage and the vaults) and
`aks.tftest.hcl` (case 1 with the real cluster module, which the others
override). They pass on Terraform 1.9 and OpenTofu 1.11.
