# Quickstart: Autoheal behind a shared Istio gateway on AKS

This guide is for an AKS cluster that another team owns, where all outside
traffic comes in through one shared Istio ingress gateway that the team runs.
The cluster stays in its subscription (the **cluster subscription**). The other
Autoheal resources go in a second subscription (the **data subscription**), and
the two VNets are not connected. The data services use public endpoints with
firewalls.

The install is four steps, in this order. Each step is a folder of
[`examples/azure/split-istio`](../examples/azure/split-istio):

| Step       | Folder     | What it does                                                                 | Who runs it |
| ---------- | ---------- | ---------------------------------------------------------------------------- | ----------- |
| 1. Infra   | `infra/`   | Postgres, Redis, storage, Key Vaults and identities in the data subscription | Deployer    |
| 2. Cluster | `cluster/` | Reads the cluster and connects the identities to it                          | Deployer    |
| 3. App     | `app/`     | Installs the chart in your namespace, behind the gateway                     | Deployer    |
| 4. Runner  | `runner/`  | Optional: VMs that run the agents' commands                                  | Deployer    |

The [runbook](azure-two-subscriptions-public-runbook.md) has every command.
This guide links to its sub-steps and says what is different behind a shared
gateway:

- No public IP and no NSG rule for Autoheal. The gateway is the way in.
- No TLS certificate in Terraform. The gateway ends TLS with its own
  certificate.
- The DNS records point at the gateway, and the gateway owner makes them.
- The chart adds Istio VirtualServices bound to the gateway. It makes no
  Gateway and no load balancer.

It uses autoheal-byoc-infra **v4.1.1** and chart **1.0.0-rc.13**.

## Before you start: what the cluster owner provides

Ask the cluster owner for these before step 1. The runbook sub-step in each
line has the commands.

1. **OIDC issuer and workload identity** on the cluster
   ([step 2](azure-two-subscriptions-public-runbook.md#step-2-check-the-cluster),
   [step 3](azure-two-subscriptions-public-runbook.md#step-3-optional-turn-on-the-cluster-features)).
   The pods sign in to Key Vault and storage as workload identities.
2. **A Secrets Store CSI driver with the Azure Key Vault provider.** The chart
   uses it to copy the vault entries into Kubernetes Secrets. The AKS Key Vault
   secrets provider add-on is this driver; a driver the team installs itself
   works too. Workload identity alone is not enough: it is only how the driver
   signs in. Without a driver, the chart can read Secrets that you create
   (`global.secrets.mode: existing`) or that External Secrets Operator writes
   (`eso`): see `docs/secrets.md` in the chart.
3. **The namespace**, with the deployer's roles on the cluster and in the
   namespace
   ([step 4b](azure-two-subscriptions-public-runbook.md#4b-make-the-namespace),
   [step 6b](azure-two-subscriptions-public-runbook.md#6b-give-the-deployer-its-roles)).
4. **Native sidecars**, when the namespace has Istio sidecar injection. The
   chart runs install Jobs. A classic sidecar keeps a Job's pod running after
   the Job's container ends, so the install never finishes. Istio's native
   sidecars (`ENABLE_NATIVE_SIDECARS=true`, on in the AKS Istio add-on) stop
   with the Job.
5. **The storage service endpoint** on the AKS subnet
   ([step 4d](azure-two-subscriptions-public-runbook.md#4d-add-the-storage-service-endpoint)),
   and after step 1, the storage network rule
   ([step 9c](azure-two-subscriptions-public-runbook.md#9c-add-the-storage-network-rule)).
   The rule needs
   `Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action`
   on the AKS subnet.
6. **The cluster's fixed public outbound addresses.** Postgres and the Key
   Vaults let in only these. With a firewall on the cluster's outbound route,
   this is the firewall's public address
   ([Other outbound types](azure-two-subscriptions-public-runbook.md#other-outbound-types)).
7. **Room for one extra pod per Deployment** for a few minutes after the
   install. The install restarts the Deployments once the sign-in settings
   exist. Without room, the old pods keep running, the install looks done, and
   sign-in does not work.
8. **The gateway**: its `<namespace>/<name>`, and its HTTPS server with hosts
   and a certificate for `<hostname>`, `auth.<hostname>` and
   `auth-app.<hostname>`. A certificate for `<hostname>` and `*.<hostname>`
   covers them, and the runner host of step 4.
9. **Which certificate the pods see** on `https://auth.<hostname>`. api-server-go
   calls that address from inside the cluster to read the login settings. When
   a private CA signed that certificate, get the CA's PEM file: step 1 needs
   it. A public CA needs nothing.

## Step 1: Infra

Do runbook steps
[1](azure-two-subscriptions-public-runbook.md#step-1-sign-in-and-set-your-values),
[6a](azure-two-subscriptions-public-runbook.md#6a-get-the-outbound-addresses)
and [7](azure-two-subscriptions-public-runbook.md#step-7-prepare-the-data-subscription)
to [9](azure-two-subscriptions-public-runbook.md#step-9-apply-the-infra), with
these changes. Skip step 5 (public IP and NSG rule).

**1b.** Leave `DNS_ZONE_ID` empty. Leave out `TLS_CERT_FILE` and
`TLS_KEY_FILE`, and take them off the `check_values` line.

**7b.** Copy `split-istio`, not `split-public`:

```bash
[ -e acme-autoheal/prod ] || cp -R autoheal-byoc-infra/examples/azure/split-istio acme-autoheal/prod
```

**8b.** Write the inputs with this block instead. `PROXY_IP` is not needed:

```bash
check_values AKS_ID AKS_SUBNET_ID EGRESS_IPS DEPLOYER_IPS
cat > "$WORK_DIR/inputs.hcl" <<EOF
namespace       = "$NAME_PREFIX"
environment     = "$ENVIRONMENT"
location        = "$LOCATION"
subscription_id = "$DATA_SUB"

existing_aks_cluster_id = "$AKS_ID"
cluster_network_path    = "public"
existing_network = {
  aks_subnet_id = "$AKS_SUBNET_ID"
}
service_accounts          = { namespace = "$K8S_NAMESPACE" }
workload_egress_ip_ranges = [$(echo "$EGRESS_IPS" | tr ' ' '\n' | sed 's/.*/"&"/' | paste -sd, -)]
deployer_ip_ranges        = [$(echo "$DEPLOYER_IPS" | tr ' ' '\n' | sed 's/.*/"&"/' | paste -sd, -)]

hostname           = "$AUTOHEAL_HOSTNAME"
edge_mode          = "istio"
create_dns_records = false
EOF
cat "$WORK_DIR/inputs.hcl"
```

Then do 8c as written.

**8d.** Run the block for your options without the `TF_VAR_tls_certificate`
lines, and take it off the `check_values` line. With Terraform Enterprise, do
not add the `tls_certificate` variable. When item 9 of
[Before you start](#before-you-start-what-the-cluster-owner-provides) gave you
a CA file, also set:

```bash
export TF_VAR_edge_ca_certificate="$(cat edge-ca.pem)"
```

It goes in the vault as `edge-ca-certificate`, and the chart mounts it in
api-server-go, so it trusts the gateway certificate.

**9b.** The gateway owner points `$AUTOHEAL_HOSTNAME`,
`auth.$AUTOHEAL_HOSTNAME` and `auth-app.$AUTOHEAL_HOSTNAME` at the gateway,
with CNAMEs or A records. `terragrunt output required_dns_records` lists the
three names.

**9c.** The cluster owner adds the storage network rule.

## Step 2: Cluster

Do runbook [step 10](azure-two-subscriptions-public-runbook.md#step-10-connect-the-identities-to-the-cluster)
as written. When the plan warns that the Key Vault secrets provider add-on is
off, that is fine if the cluster has its own CSI driver (item 2 of
[Before you start](#before-you-start-what-the-cluster-owner-provides)).

## Step 3: App

Do runbook [step 11](azure-two-subscriptions-public-runbook.md#step-11-install-the-application)
and [step 12](azure-two-subscriptions-public-runbook.md#step-12-check-that-it-works),
with this change.

**11a.** In the file the runbook writes, replace the `edge` block with this
one, with the gateway's `<namespace>/<name>`. There is no `tls` block, because
the gateway ends TLS:

```yaml
  edge:
    mode: istio
    istio:
      gateway: istio-ingress/shared-gateway
```

The chart then adds two VirtualServices on that gateway: `autoheal` for
`<hostname>` and `auth-app.<hostname>`, and `autoheal-auth` for
`auth.<hostname>`. Both go to the `autoheal-proxy` Service in your namespace.
The auth host goes to port 81 over HTTP/2, because Zitadel serves gRPC there.

To check, after 11b:

```bash
kubectl -n "$K8S_NAMESPACE" get virtualservices
curl -sS -o /dev/null -w '%{http_code}\n' "https://$AUTOHEAL_HOSTNAME"
```

The first command shows the two VirtualServices. The second must show `200`.
In step 12a, skip the `autoheal-edge` line: there is no load balancer.

## Step 4: Runner (optional)

Without a runner, the agents answer and call your integrations, but run no
commands. Do runbook
[step 14](azure-two-subscriptions-public-runbook.md#step-14-optional-add-the-sandbox-runner),
with these changes. The runner VMs reach Temporal through the gateway on
`runner.<hostname>`, over TLS, with a key that the chart's proxy checks.

**14a and 14b.** Set only the name:

```bash
export RUNNER_HOST="runner.$AUTOHEAL_HOSTNAME"
```

The rest is for the gateway owner. The gateway owner:

- adds `runner.$AUTOHEAL_HOSTNAME` to the hosts and the certificate of the
  gateway, and points it at the gateway like the other three names;
- makes sure the path to the gateway, a WAF included, offers TLS 1.3, passes
  the runner's gRPC as HTTP/2, keeps a call open for more than a minute (a
  Temporal poll lasts about one) and takes requests over 1 MB. When a WAF in
  front cannot, point the runner at an address of the gateway that skips it;
- lets the runner's outbound address in on TCP 443 when the gateway takes only
  some sources. Step 14d shows it (the `egress_ip` output).

**14c.** As written. The chart adds a third VirtualService, `autoheal-runner`.
The `curl` must show `401`: the proxy refuses a call without the key.

**14d.** The `runner` folder came with `split-istio` in step 7b. The runner
gets its own VNet with a NAT gateway and reaches the gateway over the internet.
When the gateway is reachable only from inside your network, set
`existing_subnet_id` in `runner/terragrunt.hcl` to a subnet with a route to it.
When you set `TF_VAR_edge_ca_certificate` in step 1, the runner needs the same
CA; the runbook's commands copy it.

**14e and 14f.** As written: check that the runner polls, then turn on
sandboxes.

## In a new shell

Run the runbook's
[Resume in a new shell](azure-two-subscriptions-public-runbook.md#resume-in-a-new-shell)
block without the `PROXY_IP` line, and take `PROXY_IP` off its `check_values`
line.

## When something fails

- The install hangs on a Job: check item 4 (native sidecars).
- Pods wait for Secrets, or the `secrets-sync` Job fails to mount its volume:
  check item 2 (CSI driver).
- api-server-go restarts with `x509: certificate signed by unknown authority`:
  check item 9, then set `TF_VAR_edge_ca_certificate` and apply steps 1 and 3
  again.
- The install is done but sign-in fails: check item 7, then
  `kubectl -n "$K8S_NAMESPACE" rollout restart deployment`.
- The runner logs TLS or connection errors: check the 14a and 14b list.

The runbook's [Troubleshooting](azure-two-subscriptions-public-runbook.md#troubleshooting)
covers the rest.
