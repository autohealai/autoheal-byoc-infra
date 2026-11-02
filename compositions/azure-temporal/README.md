# compositions/azure-temporal

The Temporal step, optional: one VM that runs the Temporal server, for an
install whose cluster cannot run it. The app and the runner reach it on
`<IP or dns_name>:7233` over TLS 1.3, with a key.

The VM (`modules/azure/temporal-vm`) runs Temporal against the install's
Postgres: the `temporal` and `temporal_visibility` databases that
`compositions/azure` makes, as `temporal_user`. The VM holds no state.
Temporal listens on 127.0.0.1 only. In front of it a gate (Envoy) ends TLS and
checks the key in the `authorization` header, per call:

- Any key opens the gRPC health check.
- The runner key opens the calls in `runner_allowed_methods`, the ones the
  Temporal Go SDK worker in runner-go makes, and nothing else.
- Every key gets 401 on `RegisterNamespace`, `UpdateNamespace`,
  `DeprecateNamespace`, `StartBatchOperation`, `DeleteWorkflowExecution`,
  `DeleteWorkerDeployment` and `DeleteWorkerDeploymentVersion`.
- The api-server key and the agents key open the rest of WorkflowService.
- Any other call, OperatorService included, gets 401.

The gate removes the key before the call goes on. Its access log records the
path and the key's entry and version, never the key.

The keys and the gate's certificate live in the install vault, not in the VM's
custom data. A timer on the VM reads them with the VM's own identity at boot
and every 5 minutes, and the gate reloads them without dropping connections.

This composition never reads the cluster. It creates, in `subscription_id`:

1. a resource group, unless `existing_resource_group_id` is set;
2. a VNet from `address_space` with the subnet `snet-temporal`, connected to
   nothing, and an NSG that lets in TCP 7233 from `allowed_source_cidrs` and
   the load balancer's probe, and denies the rest, SSH included;
3. a Standard load balancer with one static public IP, which forwards TCP 7233
   and gives the VM its way out on the same IP;
4. a scale set with exactly one VM, no public IP of its own, and a
   user-assigned identity;
5. in `key_vault_id`, the entries `temporal-api-server-key` and
   `temporal-agents-key`, and without `certificate_name`, `temporal-tls` (the
   gate's certificate and key) and `temporal-ca` (the private CAs);
6. Key Vault Secrets User for the VM's identity on each entry it reads: the two
   app keys, `runner-token`, the certificate and, with the private CA,
   `temporal-ca`;
7. a firewall rule `<namespace>-<environment>-<name>-temporal` on the Postgres
   server for the load balancer's IP.

The only providers are azurerm, tls and random.

## Certificate and name

Two ways:

- **Private CA** (default). We make a CA and a certificate for
  `temporal.autoheal.internal`, plus `dns_name` when set. Clients dial the IP
  or `dns_name`, check `temporal.autoheal.internal` (or `dns_name`), and trust
  the CA from the `temporal_ca_certificate` output or the entry `temporal-ca`.
  While you move to a new CA, both hold two CAs; see "Moving to a new CA".
  No DNS record is needed without `dns_name`.
- **Vault certificate**. Set `certificate_name` to a Key Vault certificate in
  `key_vault_id`, issued for `dns_name` by a CA the clients already trust, and
  set `dns_name`. Make a DNS record for `dns_name` that points at the
  `temporal_ip` output. `temporal_ca_certificate` is null.

The gate reads PEM and PKCS#12 entries and serves the newest version of the
entry.

## Key Vault network

The VM reads the vault from the load balancer's IP (`temporal_ip`), over the
internet: its VNet is connected to nothing, so a private endpoint does not
help it. The vault firewall must let that IP in.

This composition does not change the vault's network rules. They belong to
`compositions/azure`, which sets them inline on the vault, so a second owner
would undo them on each apply. After step 2 below, add `<temporal_ip>/32` to
`workload_egress_ip_ranges` of `compositions/azure` and apply it. That input
also opens the storage account and the runtime vault to the IP, and the
Postgres firewall with `cluster_network_path = public`, where it is the same
IP as our own rule. For a vault you brought (`existing_key_vault_id`), the
vault owner adds the IP. With `key_vault_network_default_action = "Allow"`
nothing is needed.

Until the IP is in, the gate does not start: the timer retries every few
minutes and the gate waits for its first good read. Nothing else on the VM
waits on the vault.

## Order

The VM reuses the databases the in-cluster Temporal used, with its workflows
and schedules. Two Temporal servers on one database break cluster membership
and shard ownership, so the two never run at once. Before every start the VM
checks the database and refuses while another Temporal server wrote a
heartbeat in the last 60 seconds.

| Step | Composition | Needs |
|------|-------------|-------|
| 1 infra | `compositions/azure` | makes Postgres with the Temporal databases, and the vault entries `temporal-db-password` and `runner-token` |
| 2 temporal | this composition, `start_temporal = false` | step 1, and Postgres open to public connections |
| 2b infra again | `compositions/azure`, with `<temporal_ip>/32` in `workload_egress_ip_ranges` | step 2 (see "Key Vault network") |
| 3 app | `compositions/app`, chart values unchanged except `temporal.server.replicaCount: 0` | step 2b |
| 4 cutover | start Temporal with run-command (below), then this composition with `start_temporal = true` | no temporal-frontend, history, matching or worker pod left in the cluster |
| 5 app again | `compositions/app`, with `global.temporal.external: true`, `global.temporal.address` = `temporal_address`, `temporal.enabled: false`, `global.edge.runner.host: ""`, and the server name, CA and key entries below | step 4 |
| 6 runner | `compositions/azure-runner`, with the outputs below | step 5 |

Steps 5 and 6 need chart 1.0.0-rc.14 or later: it has
`global.temporal.external`, and its runner-go reads `TEMPORAL_TLS_CA_FILE`.

In step 2 the VM runs only the gate; nothing touches the database. The load
balancer's probe fails while Temporal is off, so it sends no new connections
to the VM yet. Work stops from step 3 until the runner polls again after
step 6.

In step 3 the chart's `temporal-schema` Job of that revision fails its
namespace step, since no Temporal frontend is left in the cluster. The apply
does not wait for Jobs, so it still succeeds, and step 5 removes the Job.

Step 4 starts Temporal on the running VM, with no reimage:

```bash
RG=<resource_group_name output>
VMSS=<vmss_name output>
ID=$(az vmss list-instances -g "$RG" -n "$VMSS" --query '[0].instanceId' -o tsv)
az vmss run-command invoke -g "$RG" -n "$VMSS" --instance-id "$ID" \
  --command-id RunShellScript \
  --scripts "systemctl enable --now temporal-server.service temporal-namespaces.service"
```

`temporal-server` checks the database, sets up or upgrades the schema, checks
again and starts. `temporal-namespaces` then creates the `agents`, `runners`
and `notifications` namespaces if they are missing. While the in-cluster
Temporal still writes heartbeats, the check fails and the unit retries every
10 seconds. `systemctl stop temporal-server` gives up.

Then apply this composition with `start_temporal = true`. That changes the
scale set model and turns the health alert on; the VM is not touched. A later
reimage keeps Temporal on.

The app moves only once Temporal answers on the VM (step 5 after step 4):
api-server-go stops at start when it cannot reach Temporal. Step 3 is its own
apply because the app apply is atomic: if step 5 fails, Helm rolls back to
step 3, with no Temporal server in the cluster, so a rollback never starts a
second Temporal on the database.

To roll back: stop Temporal on the VM with run-command
(`systemctl disable --now temporal-server.service temporal-namespaces.service`),
apply this composition with `start_temporal = false`, then the app with the
in-cluster Temporal back (`global.temporal.external: false`,
`temporal.enabled: true`, no `replicaCount` override,
`global.edge.runner.host` as before), then the runner with its earlier inputs.

The runner takes these inputs in step 6:

```hcl
temporal_address        = <temporal_address output>
temporal_tls            = true
temporal_token          = <the vault entry runner-token, the runner_token output of compositions/azure>
temporal_server_name    = <temporal_server_name output>
temporal_ca_certificate = <temporal_ca_certificate output, or "" with certificate_name>
temporal_ip             = <temporal_ip output>
```

With `temporal_ip`, the runner VM lets only runner-go reach that IP on 7233;
sandbox containers cannot.

Put the runner's NAT IP (its `egress_ip` output) in `allowed_source_cidrs`.
For a new runner, add it after step 6 and apply this composition again. That
changes the NSG only; the VM stays.

The app reads its keys from the vault entries `temporal-api-server-key`
(api-server-go) and `temporal-agents-key` (agents-py), and the CA from
`temporal-ca`. The `key_vault_secret_names` output lists them. The chart
values that point at them come with the app.

To check the VM, from a host with access to the resource group:

```bash
az vmss run-command invoke -g "$RG" -n "$VMSS" --instance-id "$ID" \
  --command-id RunShellScript \
  --scripts "systemctl is-active temporal-edge temporal-secrets.timer temporal-server; journalctl -u temporal-secrets -u temporal-edge -u temporal-server -u temporal-namespaces -n 50 --no-pager"
```

`temporal-server` is `inactive` until step 4.

## Inputs

| Input | Default | Contents |
|-------|---------|----------|
| `subscription_id` | required | Subscription for the VM. The Postgres server must be in it, usually the data subscription of `compositions/azure`. |
| `location` | required | Azure region. The region of the Postgres server keeps database calls short. |
| `namespace`, `environment`, `name` | `name` = `autoheal` | Naming, as in `compositions/azure`. Resources are `<namespace>-<environment>-<name>-temporal...`. |
| `tags` | `{}` | Tags on everything we create. |
| `resource_group_name` | `""` | Empty means `rg-<namespace>-<environment>-<name>-temporal`. |
| `existing_resource_group_id` | `""` | A resource group in `subscription_id` to use instead of creating one. |
| `address_space` | `10.62.0.0/28` | Range of the VM's VNet, all of it for `snet-temporal`. Any private range works. |
| `allowed_source_cidrs` | required | Public ranges that may reach TCP 7233: the cluster's outbound addresses and the runner's NAT IP. At least one; not `0.0.0.0/0`. |
| `dns_name` | `""` | DNS name clients dial. You make the record, pointing at `temporal_ip`. Required with `certificate_name`. |
| `certificate_name` | `""` | A Key Vault certificate in `key_vault_id` for `dns_name`. Empty means the private CA. |
| `ca_generations` | `["1"]` | Names of the private CAs, one or two. The first signs the gate's certificate; clients trust all of them. Change it only to move to a new CA. |
| `key_vault_id` | required | Resource ID of the install vault, the one with `runner-token`. It must use Azure RBAC. |
| `api_server_key_secret_name` | `temporal-api-server-key` | Entry we write with the api-server-go key. |
| `agents_key_secret_name` | `temporal-agents-key` | Entry we write with the agents-py key. |
| `runner_key_secret_name` | `runner-token` | Entry with the runner key, written by `compositions/azure`. |
| `postgres_server_id` | required | Resource ID of the install's Postgres flexible server, in `subscription_id`. |
| `postgres_fqdn` | required | Its host name, `global.infra.database.host` in the `autoheal_values` output of `compositions/azure`. |
| `temporal_db_password` | required | Sensitive. Password of `temporal_user`, the vault entry `temporal-db-password`. |
| `runner_allowed_methods` | `null` | WorkflowService calls the runner key may make. Null means the module's list. |
| `log_analytics_workspace_id` | `""` | A Log Analytics workspace for the VM's logs. Empty sends nothing. |
| `action_group_ids` | `[]` | Action groups the health alert and the certificate alert notify. |
| `start_temporal` | `false` | Start Temporal when the VM boots. See step 4. |
| `vm_size` | `Standard_D2s_v6` | Must support accelerated networking and Premium SSD. |
| `temporal_server_image` | `public.ecr.aws/e4h3h0d9/external/temporal-server:1.29.0` | The version the chart runs. The VM pulls without a login. |
| `temporal_admin_tools_image` | `public.ecr.aws/e4h3h0d9/external/temporal-admin-tools:1.29.1-tctl-1.18.4-cli-1.5.0` | For the schema and namespace steps. |
| `proxy_image` | `public.ecr.aws/e4h3h0d9/external/envoy:distroless-v1.35.6` | The Envoy image of the gate. |

### The database password

The database password is not an output of `compositions/azure`. Read it from
the install vault and pass it in the environment, so it stays out of files:

```bash
export TF_VAR_temporal_db_password="$(az keyvault secret show \
  --vault-name <vault> --name temporal-db-password --query value -o tsv)"
```

The vault name is `global.infra.keyVault.name` in the `autoheal_values` output
of `compositions/azure`. The vault lets in only the deployer IPs given there.

## Outputs

| Output | Contents |
|--------|----------|
| `temporal_address` | `dns_name` or the IP, with `:7233`: what clients dial. |
| `temporal_ip` | The load balancer's static IP, for the DNS record, the vault firewall, the runner and allow lists. |
| `temporal_server_name` | `dns_name`, or `temporal.autoheal.internal`: the name clients check. |
| `temporal_ca_certificate` | PEM of the private CAs, one or two. Not a secret. Null with `certificate_name`. |
| `key_vault_secret_names` | The vault entries the VM and the app read. |
| `vmss_name`, `resource_group_name` | For `az vmss run-command` and `az vmss reimage`. |
| `identity_principal_id` | The VM's identity. |

The keys are not outputs; read them from the vault. The state holds the two
app keys as first made, the database password, the gate's and the CA's
private keys and a generated SSH key; keep it private. The VM's custom data
holds the database password and no key. Azure never returns custom data on
read.

## Who runs it

The deployer needs, in `subscription_id`:

- Contributor on the resource group, or the right to create it.
- The right to add firewall rules on the Postgres server
  (`Microsoft.DBforPostgreSQL/flexibleServers/firewallRules/write`, in
  Contributor on the server or its resource group).
- On the vault: Key Vault Secrets Officer, to write the entries, and the right
  to create role assignments on its entries (Key Vault Data Access
  Administrator, or Owner or User Access Administrator), and a public IP the
  vault's network rules let in.

`runner-token` must exist before the apply, and so must the vault certificate
with `certificate_name`: the role assignments are made on them. Nothing is
needed on the cluster.

## With Terragrunt

A `temporal` folder after `infra`, as in `examples/azure/split-istio/temporal`:

```hcl
inputs = {
  subscription_id      = "11111111-2222-3333-4444-555555555555"
  location             = "eastus2"
  namespace            = "acme"
  environment          = "prod"
  allowed_source_cidrs = ["198.51.100.20/32"]
  postgres_server_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
  postgres_fqdn        = "acme-prod-autoheal-db.postgres.database.azure.com"
  key_vault_id         = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/acme-prod-autoheal"
  start_temporal       = false
}
```

## Upgrading

The scale set has one VM and upgrade mode Manual, and the provider's automatic
roll is off. A change to the custom data (`start_temporal`, an image, the
database password, `runner_allowed_methods`, the entry names) changes the
scale set model only. It reaches the VM when you reimage it, at a time when
Temporal may stop for a few minutes:

```bash
az vmss update-instances -g "$RG" -n "$VMSS" --instance-ids '*'
az vmss reimage -g "$RG" -n "$VMSS" --instance-ids "$ID"
```

The reimage keeps the VM, its IP and its identity, and runs cloud-init again.
Running workflows wait and go on; their state is in Postgres.

Keys and certificates rotate without a reimage. The gate accepts the two
newest enabled versions of each key entry, and reads the entries every 5
minutes:

1. Add a new version: `az keyvault secret set --vault-name <vault> --name
   temporal-agents-key --file <file with the new key>`. Terraform ignores it.
   The file holds the key alone, with no newline at the end (write it with
   `printf %s`).
2. Wait until the gate has it. Within 5 minutes the `temporal-secrets` log
   lists the new version: `routes (keys ..., app/temporal-agents-key/<new
   version>, ...) updated`. Read it with the check command above. A line
   `skipped version <new version>` means the gate refused the key; fix it
   before going on.
3. Move the client to the new key.
4. Disable the old version: `az keyvault secret set-attributes --vault-name
   <vault> --name temporal-agents-key --version <old version> --enabled false`.

The private CA's certificate lasts two years. The first apply in its last 90
days makes a new one and writes it as a new version of `temporal-tls`; the
gate serves it within 5 minutes. Clients need nothing, since the CA stays.
A vault certificate renews in the vault, and the gate serves the new version.

### Moving to a new CA

The private CA lasts ten years, and no apply renews it. From its last year on,
each plan warns: `A private CA in ca_generations expires within a year`. Move
to a new CA before it expires, or when the CA's key may have leaked. Clients
trust both CAs while the move runs, so no client refuses the gate at any step.
The CAs are named in `ca_generations`, default `["1"]`; pick a new name, such
as `"2"`.

1. Set `ca_generations = ["1", "2"]` and apply. This makes CA 2. CA 1 still
   signs the gate's certificate. The `temporal_ca_certificate` output and the
   entry `temporal-ca` now hold both CAs.
2. Give the clients both CAs:
   - the runner: pass the new `temporal_ca_certificate` to
     `compositions/azure-runner`, apply it and reimage its VMs;
   - the app: the chart copies `temporal-ca` into the cluster every 15
     minutes. After that, restart api-server-go and agents-py, which read the
     CA when they start.
3. Set `ca_generations = ["2", "1"]` and apply. CA 2 signs a new certificate
   for the gate, written as a new version of `temporal-tls`. The gate serves
   it within 5 minutes. `temporal_ca_certificate` does not change.
4. When the gate serves the new certificate, set `ca_generations = ["2"]` and
   apply. This deletes CA 1. Later, pass the new `temporal_ca_certificate` (CA 2
   alone) to the runner and restart the app as in step 2, so they stop trusting
   CA 1. Step 4 can wait; nothing breaks until CA 1 expires.

Do not skip step 2: after step 3 a client that trusts only CA 1 refuses the
gate.

Moving to a new Temporal version means a new `temporal_server_image` and
`temporal_admin_tools_image`, then a reimage. The schema step upgrades the
databases before Temporal starts. Keep the version the chart runs.

## Tests

```bash
terraform init -backend=false
terraform test
```

`tests/temporal.tftest.hcl` runs this composition against mocked providers:
the names, the app keys and their entries, the private CA with and without
`dns_name`, the vault certificate, the VM's role assignment on each entry,
the Postgres firewall rule, the outputs the runner takes, that a new value
from Terraform does not overwrite a key in the vault, and the input checks.
`tests/ca.tftest.hcl` runs the steps of "Moving to a new CA" with the real tls
provider (it works offline). The warning in a CA's last year is the last run of
`tests/temporal.tftest.hcl`.
`tests/vm.tftest.hcl` runs `modules/azure/temporal-vm` on its own: one VM with
no public IP in the load balancer's pool, the NSG, the load balancer rules,
the units with `start_temporal` off and on, the guard's place, the gate's
config, logs and the alert.
