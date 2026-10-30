# examples/azure

A starting point for your own deployment repository on Azure. Copy this folder
into a repository you own, edit the values, and run it from your pipeline.

```text
root.hcl                     state backend, shared by every folder
prod/
  versions.hcl               the infra tag and the chart version for prod
  infra/terragrunt.hcl       cloud resources (compositions/azure)
  app/terragrunt.hcl         the chart (compositions/app)
  app/values-customer.yaml   your chart settings
split/                       the same, for an AKS cluster in another subscription, connected VNets
  cluster/terragrunt.hcl     reads that cluster and federates to it (compositions/azure-cluster)
  runner/terragrunt.hcl      the sandbox runner, optional (compositions/azure-runner)
split-public/                the same, with public endpoints instead of connected VNets
split-istio/                 the same as split-public, behind a shared Istio gateway instead of a public IP
  temporal/terragrunt.hcl    Temporal on a VM, optional (compositions/azure-temporal)
cop-standin/                 internal test stand-in for that cluster; not for customers
```

Each folder has its own state file (`autoheal/prod/infra`, `autoheal/prod/app`).
For a second environment, copy `prod/` to `staging/` and change the inputs.

`split/` and `split-public/` are for a cluster whose owner gives you one
namespace and lets you create nothing in the cluster's subscription. Every
Azure resource goes in a second subscription. With `split/` the two VNets are
peered and everything stays private; with `split-public/` they are not
connected, and the data services use public endpoints with firewalls.
`split-istio/` is `split-public/` for a cluster where one shared Istio ingress
gateway takes all outside traffic: no public IP, and the chart adds
VirtualServices on that gateway. `docs/azure-shared-istio-quickstart.md`
walks through it in four steps.
`docs/azure-subscription-options.md` in autoheal-byoc-infra compares the
layouts; `docs/azure-two-subscriptions.md` and
`docs/azure-two-subscriptions-public.md` explain each for the cluster owner.

## Which resources you bring

`prod/infra/terragrunt.hcl` creates everything apart from the DNS zone. Each
building block takes an `existing_*` ID; uncomment the ones you already have.

| You bring | Set |
|-----------|-----|
| Nothing (we create the network, AKS, Postgres, Redis, storage, Key Vault) | `network_cidr` |
| Your network | `existing_network` (subnet IDs and a free address in the AKS subnet for the proxy) |
| Your cluster, database, cache, storage or vaults | `existing_aks_cluster_id`, `existing_postgres_id`, `existing_redis_id`, `existing_storage_account_id`, `existing_key_vault_id`, `existing_runtime_key_vault_id`. With `existing_aks_cluster_id`, add a `cluster` folder as in `split/`. |
| Only your cluster, in another subscription | Start from `split/`: `existing_aks_cluster_id`, `existing_network` with the AKS subnet and a free address in it, and `network_cidr` for the VNet we create in `subscription_id`. The cluster owner does what the `required_cluster_owner_actions` output lists. |
| Only your cluster, in another subscription, with no VNet connection | Start from `split-public/`: `existing_aks_cluster_id`, `cluster_network_path = "public"`, `existing_network` with the AKS subnet and a static public IP as `proxy_ip`, and `workload_egress_ip_ranges`. No VNet is created, so no `network_cidr`. |
| Only your cluster, in another subscription, with no VNet connection, behind a shared Istio gateway | Start from `split-istio/`: as `split-public/`, but `existing_network` with the AKS subnet only, `edge_mode = "istio"` and `create_dns_records = false`. In `app/values-customer.yaml`, `global.edge.istio.gateway` is the gateway as `<namespace>/<name>`. |
| Role grants made by your administrators | `create_role_assignments = false`, then make the grants in the `required_role_assignments` output |
| DNS outside Azure DNS | `create_dns_records = false`, then create the records in the `required_dns_records` output |

A brought resource is only read. Mixes that cannot work (a brought cluster
without its network, a vault on access policies, a Postgres server older than 15)
stop the plan with a message saying what to change.

## Before the first run

1. Tools on the pipeline runner: Terraform 1.7 or later (or OpenTofu),
   Terragrunt, the `az` CLI and `kubelogin`.
2. Permissions for the identity that runs Terraform: Contributor on the
   subscription, plus User Access Administrator (or Owner) while
   `create_role_assignments = true`.
3. Edit the names in `root.hcl`, then create the state storage account once:

   ```bash
   ./scripts/bootstrap-state-azure.sh \
     --subscription    11111111-2222-3333-4444-555555555555 \
     --resource-group  rg-acme-tfstate \
     --storage-account stacmetfstate \
     --location        eastus2
   ```

   The script is in autoheal-byoc-infra. It also grants you Storage Blob Data
   Contributor on the account, because `root.hcl` reads state with Entra ID
   (`use_azuread_auth = true`). Grant the pipeline identity the same role.
4. Edit `prod/infra/terragrunt.hcl` and `prod/app/values-customer.yaml`.

## Secrets

No secret goes in these files. Pass them to the infra folder as environment
variables from your pipeline's secret store; Terraform writes them to Key Vault:

| Variable | Vault entry | When |
|----------|-------------|------|
| `TF_VAR_llm_api_key` | `llm-api-key` | When your LLM provider uses an API key and the chart's LLM gateway is off |
| `TF_VAR_postgres_admin_password` | `postgres-admin-password` | Only with `existing_postgres_id`; for a server we create, Terraform generates it |
| `TF_VAR_sso_client_secret` | `sso-client-secret` | When SSO is on |
| `TF_VAR_tls_certificate` | `tls-certificate`, `tls-private-key` | When the edge serves your own certificate; an HCL object `{ certificate = "<PEM chain>", private_key = "<PEM>" }` |
| `TF_VAR_github_app_private_key` | `github-app-private-key` | When you connect a GitHub App; the PEM, which Terraform stores base64-encoded |
| `TF_VAR_github_app_webhook_secret` | `github-app-webhook-secret` | When you connect a GitHub App |
| `TF_VAR_llm_gateway_api_key` | `gateway-api-key` | When the chart's LLM gateway is on, with any kind except `custom`. For a gateway that ignores it, such as Portkey OSS, any value. |
| `TF_VAR_llm_gateway_extra_headers` | `gateway-extra-headers` | When the gateway needs extra headers; a JSON object of strings, for example `{"x-portkey-config":"<config JSON>"}` |

To send model calls through an LLM gateway you run, such as Portkey, see
"Optional: an LLM gateway" in autoheal-byoc-infra's `docs/getting-started.md`.
It lists the gateway secrets to set and the `global.llm.gateway` block for
`values-customer.yaml`.

Terraform generates and stores the rest (database passwords, the JWT key, the
Zitadel master key, the first admin password, the OAuth keys and the tool
response server secret).

## Running it

```bash
cd prod/infra && terragrunt plan && terragrunt apply
cd ../app     && terragrunt plan && terragrunt apply
```

The app folder reads `autoheal_values` and `cluster` from the infra folder's
state. Before the infra folder has been applied, its plan uses the placeholder
outputs in the `dependency` block. The app folder logs in to AKS with
`kubelogin`; set `kubelogin_login_mode = "workloadidentity"` when the pipeline
signs in with a federated identity rather than `az login`.

With a cluster you bring (`split/`, `split-public/`), the infra folder never
reads the cluster. Run the `cluster` folder between infra and app:

```bash
cd split/infra && terragrunt apply
cd ../cluster  && terragrunt apply
cd ../app      && terragrunt apply
```

It reads the cluster, checks that the OIDC issuer and the Key Vault CSI driver
are on, federates the three workload identities to the cluster, and outputs the
cluster's endpoint and CA certificate. The app folder takes `cluster` from it.

The sandbox runner is optional and comes last. The comments at the top of
`runner/terragrunt.hcl` list what to do first: the runner host in DNS and in
the app folder's `global.edge.runner.host`, then an app apply. Then:

```bash
cd split/runner && terragrunt apply
```

Once the runner polls Temporal, set `global.sandbox.enabled: true` in
`app/values-customer.yaml` and apply the app folder again. Step 14 of
autoheal-byoc-infra's `docs/azure-two-subscriptions-public-runbook.md` has the
commands and the checks.

When the cluster cannot run the Temporal server, `split-istio/temporal` runs it
on a VM of its own, with TLS and a key on port 7233. It goes between infra and
app, with Temporal installed but off; you start it once the in-cluster Temporal
is gone, since two servers on one database break it. The comments at the top of
`temporal/terragrunt.hcl` and the README of `compositions/azure-temporal` list
the steps. The database password comes from the vault entry
`temporal-db-password` as `TF_VAR_temporal_db_password`.

## Upgrading

Change the two numbers in `prod/versions.hcl` (after staging has run them), then
run both folders again. Read the release notes in autoheal-byoc-infra's
`CHANGELOG.md` first.

## Installing with Helm or Flux instead

Run only the infra folder, then write its values to a file and install the chart
with them:

```bash
cd prod/infra && terragrunt output -raw autoheal_values_yaml > values-infra.yaml
helm upgrade --install autoheal oci://public.ecr.aws/e4h3h0d9/charts/autoheal \
  --version 1.0.0-rc.13 -n autoheal --create-namespace \
  -f values-infra.yaml -f ../app/values-customer.yaml --atomic --wait --timeout 20m
```

`values-infra.yaml` holds names, addresses and client IDs, never a secret.
With a cluster you bring, run the `cluster` folder after the infra folder as
well: it makes the federated credentials the pods sign in with.
