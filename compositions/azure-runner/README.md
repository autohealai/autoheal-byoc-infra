# compositions/azure-runner

The runner step: VMs outside the cluster that run sandboxes, where the agents
run commands. It is optional. Without it Autoheal runs with sandboxes off: the
agents answer and call integrations but run no commands.

The runner VMs run runner-go on a VM scale set (`modules/azure/runner-vmss`).
Each pulls `runner-go:chart-<chart_version>` and polls Temporal at
`temporal_address`, namespace `runners`, task queue `runner-task-queue`.

By default the runner reaches Temporal through the edge, on a hostname of its
own: the chart's `global.edge.runner.host`, on port 443, over TLS. The edge
passes the call to the chart's proxy, and the proxy passes it on to Temporal
only when it carries the runner key (`temporal_token`, the `runner_token`
output of `compositions/azure`). Any other call gets 401. Sandbox tool results
go back through Temporal as well, so the runner needs one address and one port.
The edge must offer TLS 1.3, since runner-go refuses older versions, and pass
gRPC through as HTTP/2.

The runner only dials out; nothing connects into it. This composition never
reads the cluster and needs no access to the cluster's subscription: the
Temporal address is an input, like the cluster ID is for `compositions/azure`.
It creates, in `subscription_id`:

1. a resource group, unless `existing_resource_group_id` is set;
2. unless `existing_subnet_id` is set, a VNet from `address_space` with the
   subnet `snet-runner` and a NAT gateway with a static public IP;
3. a user-assigned identity and the VM scale set, with cloud-init that installs
   Docker and runs runner-go under systemd;
4. AcrPull for the identity on `acr_id`, when set.

It has no helm or kubernetes provider. The only providers are azurerm and tls.

On the VMs, runner-go runs sandboxes only. Its lambda drivers are off
(`DISABLED_DRIVERS`), since they would run with the runner's settings, the key
included. Containers on the VMs, sandboxes included, cannot reach the instance
metadata service, so only the host can use the VM identity. The runner-go unit
adds that firewall rule before each start, and runner-go does not start without
it.

## Order

| Step | Composition | Needs |
|------|-------------|-------|
| 1 infra | `compositions/azure`, 4.1.0 or later | makes the vault entry `runner-token` and the `runner_token` output |
| 2 cluster | `compositions/azure-cluster`, for a brought cluster | step 1 |
| 3 app | `compositions/app`, with `global.edge.runner.host` in the chart values | a DNS record for the host at the edge, and the edge certificate covering it |
| 4 runner | this composition, `temporal_address = "<runner host>:443"`, `temporal_token` = the `runner_token` output | step 3, and the network owner's part |
| 5 app again | `compositions/app`, with `global.sandbox.enabled: true` in the chart values | the runner polling Temporal |

Step 3 adds the runner route to the chart's proxy, and the runner host to the
chart's Istio Gateway or Gateway API listener when the chart makes one. With a
shared Istio Gateway (`global.edge.istio.gateway`), its owner adds the host to
it. Sandboxes stay off. Until the network owner opens the path, the runner keeps
retrying; nothing fails.

Do step 5 only after the runner polls Temporal. With sandboxes on and no runner,
every agent run waits for a sandbox that never starts, then fails after about
11 minutes. To check, look in the Temporal web UI that the chart runs in the
cluster (reach it with `kubectl port-forward`) for a poller on task queue
`runner-task-queue` in namespace `runners`, or on a runner VM:

```bash
RG=<resource group>
VMSS=<namespace>-<environment>-autoheal-runner
for id in $(az vmss list-instances -g "$RG" -n "$VMSS" --query '[].instanceId' -o tsv); do
  echo "== VM $id"
  az vmss run-command invoke -g "$RG" -n "$VMSS" --command-id RunShellScript --instance-id "$id" \
    --scripts "systemctl is-active runner-go; journalctl -u runner-go -n 50 --no-pager"
done
```

Instance IDs are not always 0, 1 and so on, so the loop asks Azure for them.

To stop sandboxes, set `global.sandbox.enabled: false` and apply the app.

### Without the edge: the runner load balancers

The chart can also put the Temporal frontend on an internal load balancer at a
private address in the AKS subnet (`temporalFrontendLoadBalancer`, see "Runner
load balancers" in the chart's `docs/prerequisites.md`). Then set
`temporal_address = "<that address>:7233"`, `temporal_tls = false` and no
`temporal_token`. Temporal there has no TLS and no login, so the address must be
a private IPv4 address. The plan stops on a public address, and on a host name,
which could resolve to a public one. The runner VNet needs a private connection
to the cluster's VNet. The same goes for an `http://` `tool_response_url`.

## The network owner's part

`required_network_owner_actions` lists it in plain sentences. In short:

- Give the runner a route to the runner host. With a private edge, connect the
  runner VNet to the edge's network, through the hub or a VNet peering; with a
  hub firewall both directions cross the firewall, so the return path matches,
  and `address_space` must not overlap anything on that path. With a public
  edge, the runner reaches it through its NAT gateway.
- Allow the runner subnet, or its NAT gateway's IP (`egress_ip`) for a public
  edge, to the runner host on TCP 443.
- Point the runner host at the edge like the app hostnames. The edge
  certificate must cover it, and a shared Istio Gateway must list it in its
  hosts. When a private CA signed the certificate, pass the CA as
  `temporal_ca_certificate`.

The key keeps Temporal closed to anyone else who reaches the edge, and TLS keeps
the key, the git tokens and the command output off the wire. With the runner
load balancers there is neither, so do not put 7233 on the internet, by a
firewall DNAT or a public load balancer.

Outbound, the runner needs the image registry (`public.ecr.aws`, or your ACR),
the git hosts and the endpoints the tools call. In the VNet we create, that
traffic leaves from `egress_ip`, the NAT gateway's address, unless a route sends
it through your firewall; then those go on the firewall's allow list. With
`existing_subnet_id` your routes decide, and no NAT gateway is created.

The VMs get no public IP, and the subnet gets no network security group. Add
one on the subnet if your policy needs it; the runner needs no inbound rule.

## Inputs

| Input | Default | Contents |
|-------|---------|----------|
| `subscription_id` | required | Subscription for the runner, usually the data subscription. `existing_subnet_id` must be in it. |
| `location` | required | Azure region. With `existing_subnet_id`, the subnet's region. |
| `namespace`, `environment`, `name` | `name` = `autoheal` | Naming, as in `compositions/azure`. Resources are `<namespace>-<environment>-<name>-runner...`. |
| `tags` | `{}` | Tags on everything we create. |
| `resource_group_name` | `""` | Empty means `rg-<namespace>-<environment>-<name>-runner`. |
| `existing_resource_group_id` | `""` | A resource group in `subscription_id` to use instead of creating one. |
| `temporal_address` | required | `<host>:<port>`: the chart's `global.edge.runner.host` and 443. With the runner load balancers, their private IPv4 address and 7233. |
| `temporal_tls` | `true` | Dial over TLS. `false` only with the runner load balancers, on a private IPv4 address. |
| `temporal_token` | `""` | Sensitive. The runner key: the `runner_token` output of `compositions/azure`. Required with `temporal_tls`, empty without. Letters and digits, at least 32. |
| `temporal_server_name` | `""` | Host name to check in the edge certificate. Empty means the host of `temporal_address`. |
| `temporal_ca_certificate` | `""` | PEM of a private CA that signed the edge certificate, such as the `edge_ca_certificate` of `compositions/azure`. The runner trusts it on top of the public CAs. |
| `tool_response_url` | `""` | Empty sends tool results through Temporal. With the runner load balancers it may be `http://<address>:8083/api/v1/internal/sandbox-tool-responses`. An `http://` URL must be a private IPv4 address; `https://` may be any host. |
| `chart_version` | required | The chart version of the app step. The image tag is `chart-<chart_version>`. |
| `runner_image` | `public.ecr.aws/e4h3h0d9/app/runner-go` | Repository, without a tag or digest. For your ACR copy, also set `acr_id`. |
| `runner_image_tag` | `""` | Overrides `chart-<chart_version>`. |
| `sandbox_image` | `""` | One sandbox image reference, to pre-pull at boot. |
| `acr_id` | `""` | The ACR of the chart's `global.imageRegistry`: AcrPull for the identity, and a registry login on the VMs. runner-go pulls the sandbox image from that registry, so the VMs log in even when `runner_image` is public. |
| `create_role_assignments` | `true` | `false` lists the AcrPull grant in `required_role_assignments` instead. |
| `existing_subnet_id` | `""` | A subnet in `subscription_id` that already has a route to the runner host and outbound access. No VNet or NAT gateway is created. |
| `address_space` | `10.61.0.0/24` | Range of the VNet we create, all of it for `snet-runner`. |
| `vm_size` | `Standard_D4s_v6` | Must support accelerated networking. |
| `instance_count` | `1` | Runner VMs. Each is an independent Temporal worker. |
| `os_disk_size_gb` | `1024` | P30. A smaller disk makes the first chat after a boot wait on disk writes. |
| `max_concurrent_activities` | `20` | Activities per VM at once. |
| `admin_ssh_public_key` | `""` | Empty generates a key pair; the private key stays in the state only. |

## Outputs

| Output | Contents |
|--------|----------|
| `egress_ip` | The NAT gateway's public IP, for allow lists on a public edge, git hosts and tool endpoints. Null with `existing_subnet_id`. |
| `subnet_id`, `subnet_cidr` | The runner subnet and its range, the source of the network rule. |
| `identity_principal_id`, `identity_client_id` | The runner identity. |
| `vmss_id` | The VM scale set. |
| `required_network_owner_actions` | What the network owner must do, as readable lines. |
| `required_role_assignments` | The AcrPull grant, only with `acr_id` and `create_role_assignments = false`. |

None of the outputs holds a secret. `temporal_token` and a generated SSH
private key are in the state, and the key is in the VMs' custom data, which
Azure never returns on read.

## Who runs it

The deployer needs, in `subscription_id`, Contributor on the resource group (or
the right to create it), and with `existing_subnet_id` the right to join the
subnet (`Microsoft.Network/virtualNetworks/subnets/join/action`, in Network
Contributor) and read it. The AcrPull grant needs Role Based Access Control
Administrator or User Access Administrator on the registry; without it, set
`create_role_assignments = false`. Nothing is needed on the cluster.

## With Terragrunt

A `runner` folder after `app`, as in `examples/azure/split`. It reads the key
from the `infra` folder and nothing from the cluster:

```hcl
dependency "infra" {
  config_path = "../infra"
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs = { runner_token = "pendingpendingpendingpendingpending" }
}

inputs = {
  subscription_id  = "11111111-2222-3333-4444-555555555555"
  location         = "eastus2"
  namespace        = "acme"
  environment      = "prod"
  temporal_address = "runner.autoheal.acme.example:443"
  temporal_token   = dependency.infra.outputs.runner_token
  chart_version    = local.v.chart_version
}
```

The `app` folder's chart values set `global.edge.runner.host` to the same host.

`shallow` matters on an upgrade from 4.0.x: the `infra` state has outputs but
no `runner_token` until the 4.1.0 infra apply, and without it the runner plan
fails. The apply never uses the placeholder.

## Upgrading

Bump `chart_version` with the app's. The scale set's upgrade mode is Manual, so
the apply updates and reimages each VM in place (the azurerm features
`roll_instances_when_required` and `reimage_on_manual_upgrade`, both on by
default). A sandbox running on a VM during the reimage fails.

## Tests

```bash
terraform init -backend=false
terraform test
```

`tests/runner.tftest.hcl` plans against mocked providers: the network we create,
a brought subnet and resource group, the image and the registry login, the edge
path and the runner load balancers, a public edge, the tool-result URL, the
network owner's lines, the AcrPull grant listed instead of made, and the input
checks (address, URL, images, server name, resource IDs, address space, a public
address or a host name without TLS, an `http://` tool-result URL that is not a
private address, the key with and without TLS, the key's characters, the CA, a
resource group or subnet in another subscription).
