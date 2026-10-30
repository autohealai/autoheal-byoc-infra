# compositions/azure-temporal

The Temporal step, optional: one VM that runs the Temporal server, for an
install whose cluster cannot run it. The app and the runner reach it on
`<public IP>:7233` over TLS 1.3, with a key.

The VM (`modules/azure/temporal-vm`) runs Temporal against the install's
Postgres: the `temporal` and `temporal_visibility` databases that
`compositions/azure` makes, as `temporal_user`. The VM holds no state.
Temporal listens on 127.0.0.1 only. In front of it a proxy (Envoy) ends TLS and
checks the key in the `authorization` header:

- The app key opens the worker API in every namespace.
- The runner key opens `GetSystemInfo`, which the Go SDK calls first with no
  namespace header, and the worker API in the `runners` namespace.
- Both open the gRPC health check.
- Any other call, the admin API included, gets 401.

The namespace check reads the `temporal-namespace` header, which a stock SDK
sets, so it keeps a misconfigured runner out of the other namespaces. It is not
a hard boundary: a hand-made gRPC client with the runner key can send the
header and another namespace in the body, and Envoy cannot read the body.

This composition never reads the cluster. It creates, in `subscription_id`:

1. a resource group, unless `existing_resource_group_id` is set;
2. a VNet from `address_space` with the subnet `snet-temporal`, connected to
   nothing, and an NSG that lets in TCP 7233 from `allowed_source_cidrs` and
   denies the rest, SSH included;
3. a static public IP and the VM, with cloud-init that installs Docker and the
   Temporal, schema, namespace and proxy units;
4. a firewall rule `<namespace>-<environment>-<name>-temporal` on the Postgres
   server for the VM's IP;
5. with `key_vault_id`, the vault entries `temporal-app-key` and `temporal-ca`.

It also makes the app key, a private CA and the proxy's certificate for
`temporal.autoheal.internal`. Clients dial the IP and check that name, so no
DNS record is needed. The only providers are azurerm, tls and random.

## Order

The VM reuses the databases the in-cluster Temporal used, with its workflows
and schedules. Two Temporal servers on one database break cluster membership
and shard ownership, so the two never run at once.

| Step | Composition | Needs |
|------|-------------|-------|
| 1 infra | `compositions/azure` | makes Postgres with the Temporal databases, the vault entries `temporal-db-password` and `runner-token`, and the `runner_token` output |
| 2 temporal | this composition, `start_temporal = false` | step 1, and Postgres open to public connections |
| 3 app | `compositions/app`, chart values unchanged except `temporal.server.replicaCount: 0` | step 2 |
| 4 temporal again | this composition, `start_temporal = true` | no temporal-frontend, history, matching or worker pod left in the cluster |
| 5 app again | `compositions/app`, with `global.temporal.external: true`, `global.temporal.address` = `temporal_address`, `temporal.enabled: false` and `global.edge.runner.host: ""` | step 4 |
| 6 runner | `compositions/azure-runner`, with the outputs below | step 5 |

In step 2 the VM runs only the proxy; nothing touches the database. Step 4
replaces the VM with one that sets up or upgrades the schema, starts Temporal
and creates the `agents`, `runners` and `notifications` namespaces if they are
missing. The public IP stays. Work stops from step 3 until the runner polls
again after step 6.

The app moves only once Temporal answers on the VM (step 5 after step 4):
api-server-go stops at start when it cannot reach Temporal. Step 3 is its own
apply because the app apply is atomic: if step 5 fails, Helm rolls back to
step 3, with no Temporal server in the cluster, so a rollback never starts a
second Temporal on the database.

To roll back: apply this composition with `start_temporal = false`, then the
app with the in-cluster Temporal back (`global.temporal.external: false`,
`temporal.enabled: true`, no `replicaCount` override, `global.edge.runner.host`
as before), then the runner with its earlier inputs.

The runner takes these inputs in step 6:

```hcl
temporal_address        = <temporal_address output>
temporal_tls            = true
temporal_token          = <runner_token output of compositions/azure>
temporal_server_name    = <temporal_server_name output>
temporal_ca_certificate = <temporal_ca_certificate output>
```

Put the runner's NAT IP (its `egress_ip` output) in `allowed_source_cidrs`.
For a new runner, add it after step 6 and apply this composition again. That
changes the NSG only; the VM stays.

The chart reads the app key and the CA from the install vault, as the entries
`temporal-app-key` and `temporal-ca` (`global.temporal.keyVaultEntry` and
`caVaultEntry`). Set `key_vault_id` to that vault and this composition writes
them. Without it, write them yourself from the outputs before step 5.

To check the VM, from a host with access to the resource group:

```bash
RG=rg-<namespace>-<environment>-autoheal-temporal
VM=<namespace>-<environment>-autoheal-temporal
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript \
  --scripts "systemctl is-active temporal-schema temporal-server temporal-namespaces temporal-edge; journalctl -u temporal-schema -u temporal-server -n 50 --no-pager"
```

`temporal-server` is `inactive` while `start_temporal` is false.

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
| `runner_token` | required | Sensitive. The `runner_token` output of `compositions/azure`. Letters and digits, at least 32. |
| `postgres_server_id` | required | Resource ID of the install's Postgres flexible server, in `subscription_id`. |
| `postgres_fqdn` | required | Its host name, `global.infra.database.host` in the `autoheal_values` output of `compositions/azure`. |
| `temporal_db_password` | required | Sensitive. Password of `temporal_user`, the vault entry `temporal-db-password`. |
| `key_vault_id` | `null` | A Key Vault to write `temporal-app-key` and `temporal-ca` to, such as the install vault. Null writes nothing. |
| `start_temporal` | `false` | Start Temporal on the VM. Changing it replaces the VM. |
| `vm_size` | `Standard_D2s_v6` | Must support accelerated networking and Premium SSD. |
| `temporal_server_image` | `public.ecr.aws/e4h3h0d9/external/temporal-server:1.29.0` | The version the chart runs. The VM pulls without a login. |
| `temporal_admin_tools_image` | `public.ecr.aws/e4h3h0d9/external/temporal-admin-tools:1.29.1-tctl-1.18.4-cli-1.5.0` | For the schema and namespace steps. |
| `proxy_image` | `public.ecr.aws/e4h3h0d9/external/envoy:distroless-v1.35.6` | The Envoy image of the chart's proxy. |

### The database password and the runner key

`compositions/azure` makes both. The runner key is its `runner_token` output;
with Terragrunt, read it through a `dependency` block, as below. Without
Terragrunt:

```bash
terraform -chdir=<infra folder> output -raw runner_token
```

The database password is not an output. Read it from the install vault and
pass it in the environment, so it stays out of files:

```bash
export TF_VAR_temporal_db_password="$(az keyvault secret show \
  --vault-name <vault> --name temporal-db-password --query value -o tsv)"
```

The vault name is `global.infra.keyVault.name` in the `autoheal_values` output
of `compositions/azure`. The vault lets in only the deployer IPs given there.

## Outputs

| Output | Contents |
|--------|----------|
| `temporal_address` | `<public IP>:7233`, what clients dial. |
| `temporal_server_name` | `temporal.autoheal.internal`, the name clients check in the certificate. |
| `temporal_ca_certificate` | PEM of the private CA. Not a secret. |
| `temporal_app_key` | Sensitive. The app key. Also in the vault entry `temporal-app-key` with `key_vault_id`. |
| `public_ip` | The VM's public IP, for allow lists on outbound firewalls. |

The first three go to `compositions/azure-runner` under the same names. The
state holds the app key, the runner key, the database password, the proxy's
private key, the CA's private key and a generated SSH key; keep it private.
The VM's custom data holds the keys and the password too. Azure never returns
custom data on read.

## Who runs it

The deployer needs, in `subscription_id`:

- Contributor on the resource group, or the right to create it.
- The right to add firewall rules on the Postgres server
  (`Microsoft.DBforPostgreSQL/flexibleServers/firewallRules/write`, in
  Contributor on the server or its resource group).
- With `key_vault_id`, Key Vault Secrets Officer on the vault, and a public IP
  the vault's network rules let in.

Nothing is needed on the cluster.

## With Terragrunt

A `temporal` folder after `infra`, as in `examples/azure/split-istio/temporal`.
It reads the runner key from the `infra` folder:

```hcl
dependency "infra" {
  config_path = "../infra"
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs = { runner_token = "pendingpendingpendingpendingpending" }
}

inputs = {
  subscription_id      = "11111111-2222-3333-4444-555555555555"
  location             = "eastus2"
  namespace            = "acme"
  environment          = "prod"
  allowed_source_cidrs = ["198.51.100.20/32"]
  runner_token         = dependency.infra.outputs.runner_token
  postgres_server_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
  postgres_fqdn        = "acme-prod-autoheal-db.postgres.database.azure.com"
  start_temporal       = false
}
```

## Upgrading

Any change to the VM's custom data replaces the VM: `start_temporal`, the
runner key, the database password, an image or the proxy's certificate. The
public IP and the firewall rule stay, so clients keep working once the new VM
is up, a few minutes. Running workflows wait and go on; their state is in
Postgres.

The proxy's certificate lasts two years. The first apply in its last 90 days
makes a new one and replaces the VM. Clients need nothing, since the CA stays.
The CA lasts ten years. The first apply in its last year makes a new CA and a
new certificate. Then pass the new `temporal_ca_certificate` to the runner and
the app, or they refuse the proxy.

Moving to a new Temporal version means a new `temporal_server_image` and
`temporal_admin_tools_image`. The schema unit upgrades the databases before
Temporal starts. Keep the version the chart runs.

## Tests

```bash
terraform init -backend=false
terraform test
```

`tests/temporal.tftest.hcl` plans this composition against mocked providers:
the names, the app key and the certificate, the Postgres firewall rule, the
vault entries with and without `key_vault_id`, the outputs the runner takes,
and the input checks (empty or open `allowed_source_cidrs`, a range with host
bits, a short runner key, Postgres in another subscription, a bad vault ID).
`tests/vm.tftest.hcl` plans `modules/azure/temporal-vm` on its own: the NSG,
the units with `start_temporal` off and on, the Temporal config and the
proxy's routes.
