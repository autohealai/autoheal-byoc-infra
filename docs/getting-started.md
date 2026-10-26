# Installing Autoheal on your own cloud, step by step

A guide to installing Autoheal inside your own Azure subscription or AWS account
(BYOC, "bring your own cloud"): the cloud resources first, then the application.
No prior Terraform experience is assumed. The general steps come first, then the
Azure steps, then the AWS steps.

## What you end up with

Two folders in a repository you own, each with its own state:

- `prod/infra` creates the cloud resources, or reads the ones you already have:
  network, Kubernetes cluster (AKS or EKS), PostgreSQL, Redis, storage, the
  secret store (Key Vault or Secrets Manager), workload identities, DNS
  records, and every secret the application reads, written to the secret store.
- `prod/app` installs the Autoheal chart into the cluster with the values the
  infra folder outputs and your own `values-customer.yaml`.

Without a sandbox runner, the agents answer and call the integrations you
connect, but run no shell commands or skill scripts, and say so when a step
needs one. On Azure, an optional `prod/runner` folder (`compositions/azure-runner`)
adds runner VMs that reach Temporal through the edge; see its README and
`examples/azure/split/runner`.

You drive both with **Terragrunt**, a thin wrapper around Terraform, from your
laptop for a first try or from a pipeline for a real install.

---

## Before you start

### 1. Install the command-line tools

| Tool | What it is for | Install |
|------|----------------|---------|
| Terraform (1.7 or later) | creates the infrastructure | https://developer.hashicorp.com/terraform/install |
| Terragrunt | runs each folder with its backend and inputs | https://terragrunt.gruntwork.io/docs/getting-started/install/ |
| `az` CLI (Azure) | signs in to Azure | https://learn.microsoft.com/cli/azure/install-azure-cli |
| `kubelogin` (Azure) | logs in to AKS with Entra ID for the chart install | https://azure.github.io/kubelogin/install.html |
| `aws` CLI (AWS) | signs in to AWS and logs in to EKS for the chart install | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |

On AWS, use Terraform or OpenTofu 1.10 or later: `examples/aws/root.hcl` locks
state with an S3 lock file.

Terraform is the tested CLI. OpenTofu also works; it resolves providers from the
OpenTofu registry and regenerates `.terraform.lock.hcl` on `init`.

```bash
terraform version     # 1.7 or later
terragrunt --version
az version            # Azure
kubelogin --version   # Azure
aws --version         # AWS
```

### 2. Check your permissions (Azure)

A missing role fails the apply part way through, so check first. The AWS
permissions are in the AWS steps.

- With `create_role_assignments = true` (the default) Terraform makes every
  role grant itself, which needs `Microsoft.Authorization/roleAssignments/write`.
  Contributor alone does not have it. Your identity must be **Owner**, or
  **Contributor + User Access Administrator**, on the subscription.
- If your administrators make role grants, set `create_role_assignments = false`.
  Contributor is then enough. The `required_role_assignments` output lists the
  grants to make, and the apply stops until they exist.

### 3. One-time subscription setup (Azure)

Register the resource providers (harmless to re-run):

```bash
for ns in Microsoft.ContainerService Microsoft.DBforPostgreSQL Microsoft.Cache \
          Microsoft.Storage Microsoft.KeyVault Microsoft.ContainerRegistry \
          Microsoft.Network Microsoft.ManagedIdentity Microsoft.Compute; do
  az provider register --namespace "$ns"
done
```

Pick a region where PostgreSQL Flexible Server, Azure Managed Redis and AKS are
all offered, and check the regional vCPU quota for the node pool (default two to
four `Standard_D4s_v6` nodes).

> **Cost and time.** `apply` creates billable resources. A first apply takes
> roughly 20 to 30 minutes; the cluster and Redis are the slow parts. `plan` is
> free and creates nothing.

### 4. Decide what you bring

The infra folder creates everything you do not name. For each building block
you already have, set its `existing_*` ID in `prod/infra/terragrunt.hcl`:

| You bring | Set |
|-----------|-----|
| Nothing | `network_cidr` (the range for the new network) |
| Your network | `existing_network`: the AKS, Postgres and private endpoint subnet IDs, and in `loadbalancer` mode a free address in the AKS subnet for the proxy (`proxy_ip`) |
| Your cluster, database, cache, storage or vaults | `existing_aks_cluster_id`, `existing_postgres_id`, `existing_redis_id`, `existing_storage_account_id`, `existing_key_vault_id`, `existing_runtime_key_vault_id` |

Is your AKS cluster in a subscription where Autoheal may only use one
namespace? Read [Choosing a subscription layout](azure-subscription-options.md).
Start from `examples/azure/split` (connected VNets) or
`examples/azure/split-public` (public endpoints) instead of `prod`. For public
endpoints on a cluster you already have,
[the runbook](azure-two-subscriptions-public-runbook.md) gives every command.
Behind a shared Istio gateway, start from `examples/azure/split-istio` and
follow [the shared Istio gateway quickstart](azure-shared-istio-quickstart.md).

With `existing_aks_cluster_id` the infra folder never reads the cluster. A third
folder, `cluster` (`compositions/azure-cluster`), runs between infra and app: it
reads the cluster, federates the workload identities to it and gives the app
folder the cluster's endpoint. `examples/azure/split` has it.

We never create a DNS zone. Set `existing_dns_zone_id` to the Azure DNS zone that
holds your hostname, or set `create_dns_records = false` and create the records
listed in the `required_dns_records` output yourself.

On AWS the building blocks and their `existing_*` ARNs are in the table in
`examples/aws/README.md`, and `existing_dns_zone_id` is a Route 53 hosted zone
ID.

---

## Azure / AKS

### Step 1: Sign in to Azure

```bash
az login
az account set --subscription "<subscription-id>"   # az account show --query id -o tsv
```

### Step 2: Copy the example into your repository

Copy `examples/azure` from a released tag into a repository you own:

```bash
git clone --branch v4.1.1 https://github.com/autohealai/autoheal-byoc-infra.git
mkdir acme-autoheal && cp -r autoheal-byoc-infra/examples/azure/. acme-autoheal/
cd acme-autoheal
```

### Step 3: Create the state storage account (one time)

Edit `root.hcl`: pick the resource group, storage account (3 to 24 lowercase
letters and digits, globally unique) and container names. Then create them:

```bash
../autoheal-byoc-infra/scripts/bootstrap-state-azure.sh \
  --subscription    "<subscription-id>" \
  --resource-group  rg-acme-tfstate \
  --storage-account stacmetfstate \
  --location        eastus2
```

The script is idempotent. It also grants you Storage Blob Data Contributor on
the account, because `root.hcl` reads state with Entra ID. A pipeline identity
needs the same grant.

### Step 4: Fill in your settings

- `prod/versions.hcl`: the infra tag and the chart version. Keep the two
  numbers the example carries; they are a published, tested pair. Change them
  only to upgrade.
- `prod/infra/terragrunt.hcl`: `namespace` (your short name, e.g. `acme`; it
  starts every resource name), `environment` (e.g. `prod`; not the region),
  `subscription_id`, `location`, `hostname`, `edge_mode`, the `existing_*` IDs
  from "Decide what you bring", sizing, and the network paths:
  `private_endpoints_enabled = true` and `deployer_ip_ranges` set to the public
  egress address of the machine that runs Terraform.
- Secrets, as environment variables, never in a file:

  ```bash
  export TF_VAR_llm_api_key="..."               # if your LLM provider uses a key; not with an LLM gateway
  export TF_VAR_postgres_admin_password="..."   # only with existing_postgres_id
  export TF_VAR_llm_gateway_api_key="..."       # only with an LLM gateway; see "Optional: an LLM gateway"
  export TF_VAR_llm_gateway_extra_headers="..." # only if the gateway needs headers
  ```

**Backup, high availability and encryption.** The defaults keep the data tier
small (7-day local database backup, no standby, Microsoft-managed keys). For a
real install set the `postgres_*`, `blob_*` and `key_vault_*` inputs described in
`compositions/azure/variables.tf`. Decide these before the first apply; they
cannot be changed later:

- `postgres_geo_redundant_backup_enabled`: copy database backups to the paired
  region. Create time only.
- `cmk_enabled`: encrypt the database and storage with a key you own (needs
  `key_vault_purge_protection_enabled = true`). Create time only on the
  database.
- `key_vault_soft_delete_retention_days` and `key_vault_purge_protection_enabled`:
  how long a deleted vault stays recoverable, and whether it can ever be purged.
  `runtime_key_vault_soft_delete_retention_days` and
  `runtime_key_vault_purge_protection_enabled` do the same for the runtime vault,
  where api-server-go keeps the integration credentials users enter; purge
  protection follows the install vault unless you set it.

### Step 5: Plan and apply the infra folder

```bash
cd prod/infra
terragrunt plan
terragrunt apply
```

Read the plan before typing `yes`. If the plan stops with an error, it names the
input to change (a missing subnet, an address outside the AKS subnet, no path to
the vault, and so on).

With `create_role_assignments = false` the first apply stops after creating the
identities and prints the missing grants. Have them made, then run
`terragrunt apply` again.

With a cluster you bring, the cluster owner now does what
`terragrunt output required_cluster_owner_actions` lists. Then apply the
`cluster` folder:

```bash
cd ../cluster
terragrunt apply
terragrunt output federated_credentials   # one line per chart service account
```

### Step 6: Check the outputs

```bash
terragrunt output required_role_assignments   # empty when Terraform made the grants
terragrunt output required_dns_records        # empty when Terraform made the records
terragrunt output -raw autoheal_values_yaml   # what the chart receives; no secrets
```

### Step 7: Install the application

Edit `prod/app/values-customer.yaml` (admin email, LLM, SSO, sizing). Do not set
`global.infra`; those values come from the infra folder. For an LLM gateway, see
"Optional: an LLM gateway" below.

`global.llm.offeredModels` lists the models that agents may use, comma
separated; the first is the default for an agent that names no model. Each
name must be a deployment on the resource, such as `gpt-5-mini`. Without it,
agent runs fail with `this deployment offers no models`.

For `provider: azure-openai`, `global.llm.endpoint` is the resource's v1
endpoint, ending in `/openai/v1/`, such as
`https://acme-openai.openai.azure.com/openai/v1/`. For `anthropic-foundry`, it
ends in `/anthropic/`. The same resource also needs an embedding deployment
named `text-embedding-3-large`, which Autoheal uses to find related
investigations. To use another deployment, set `global.llm.embeddingModel` to
`azure-openai:<deployment>`; it must return 1024 dimensions. Then:

```bash
cd ../app
terragrunt plan
terragrunt apply
```

The app folder logs in to the cluster with `kubelogin` using your `az login`
session. In a pipeline that signs in with a federated identity, set
`kubelogin_login_mode = "workloadidentity"` in `prod/app/terragrunt.hcl`.

To install with Helm or Flux instead of the app folder, see
`examples/azure/README.md`.

### Step 8: Check the cluster (optional)

```bash
az aks get-credentials --resource-group <resource_group> --name <name>
kubelogin convert-kubeconfig -l azurecli
kubectl get pods -n autoheal
```

`<resource_group>` and `<name>` are in `terragrunt output cluster` in
`prod/infra`.

### Optional: an LLM gateway

By default agents-py calls the LLM provider named in `global.llm` directly.
With an LLM gateway, such as Portkey, LiteLLM, OpenRouter or Helicone, agents-py
sends every model and embeddings call to the gateway instead, and the gateway
calls the provider. Use one to keep the provider keys, routing, retries,
fallbacks, budgets and request logs in one place.

You need:

- autoheal chart 1.0.0-rc.3 or later in `prod/versions.hcl`. Older charts
  reject `global.llm.gateway`.
- A gateway you run. It is not part of the install. The agents-py pods must
  reach it, for example as a service in its own namespace of the AKS cluster,
  and it needs outbound access to the provider. Portkey OSS listens on port
  8787. Its image is `portkeyai/gateway` on Docker Hub. The same image, copied
  unchanged, is in the Autoheal registry for networks that allow
  `public.ecr.aws` but not Docker Hub:
  `public.ecr.aws/e4h3h0d9/external/portkey-gateway:1.15.2`
  (`sha256:97f094d9c8a764cbfaa2a7138c0017b247ca923bb06db1b4c13b7f8a33b5200d`).
  For a cluster without internet access, mirror it into your registry.

**1. Store the gateway secrets.** Set them with the other secrets from Step 4,
then plan and apply `prod/infra` again. Terraform writes them to Key Vault.

| Gateway | `TF_VAR_llm_gateway_api_key` | `TF_VAR_llm_gateway_extra_headers` |
|---------|------------------------------|------------------------------------|
| Portkey OSS, which you host | any value; Portkey OSS ignores it | `{"x-portkey-config":"<config>"}`, which carries the routing and the provider keys |
| Hosted Portkey, with a default config on the API key | the Portkey API key | not set |
| LiteLLM, OpenRouter, Helicone or another kind the chart knows | the gateway key | only if the gateway needs more headers |
| A custom gateway that takes only headers | not set | the headers, as a JSON object of strings |

With the gateway on, `TF_VAR_llm_api_key` is not needed: the gateway holds the
provider keys.

For Portkey OSS the header holds the whole config as one JSON string. This
config sends Claude models to Azure AI Foundry and every other model, the
embeddings included, to Azure OpenAI:

```json
{
  "request_timeout": 120000,
  "strategy": {
    "mode": "conditional",
    "conditions": [{"query": {"params.model": {"$regex": "^claude"}}, "then": "claude"}],
    "default": "azure-openai"
  },
  "targets": [
    {"name": "claude", "provider": "anthropic", "api_key": "<key>",
     "custom_host": "https://<resource>.services.ai.azure.com/anthropic/v1"},
    {"name": "azure-openai", "provider": "openai", "api_key": "<key>",
     "custom_host": "https://<resource>.openai.azure.com/openai/v1"}
  ]
}
```

Save it as `portkey-config.json`, outside the repository since it holds the
provider keys, and set the variables from it:

```bash
export TF_VAR_llm_gateway_api_key="unused"
export TF_VAR_llm_gateway_extra_headers="$(jq -cn --arg cfg "$(jq -c . portkey-config.json)" '{"x-portkey-config": $cfg}')"
```

In a pipeline, keep the header value in the pipeline's secret store like the
other secrets.

**2. Turn the gateway on** in `prod/app/values-customer.yaml`. `global.llm`
still names the provider and the model:

```yaml
global:
  llm:
    provider: azure-openai
    model: gpt-5-mini
    offeredModels: gpt-5-mini
    gateway:
      enabled: true
      kind: portkey     # portkey, litellm, openrouter, helicone, pydantic or custom
      baseUrl: http://portkey-gateway.llm-gateway.svc.cluster.local:8787/v1
```

- `kind` sets how agents-py sends the gateway key: `portkey` as
  `x-portkey-api-key`, `helicone` as `Helicone-Auth`, the others as
  `Authorization: Bearer`.
- `baseUrl` is the gateway's OpenAI-compatible root, ending in `/v1`. Claude
  models use the gateway's Anthropic Messages route: `anthropicBaseUrl` when
  set, otherwise `baseUrl` without `/v1`.
- `global.llm.endpoint` and `global.llm.apiKeyVaultEntry` are not read and can
  be left out.
- Embeddings go to the gateway with the model name `text-embedding-3-large`, or
  the name after `azure-openai:` in `global.llm.embeddingModel`. The gateway
  must route it to a model that returns 1024 dimensions; the config above sends
  it to Azure OpenAI. agents-py sends an embedding model through the gateway
  only when it starts with `azure-openai:`, so the chart refuses any other.
- Do not set the vault entry names. When `TF_VAR_llm_gateway_extra_headers` is
  set, the infra folder's `autoheal_values` already sets `extraHeadersVaultEntry`,
  and an empty `apiKeyVaultEntry` when `TF_VAR_llm_gateway_api_key` is not set.

**3. Apply `prod/app` again.** Only the agents-py pods restart. With the gateway
on, agents-py does not retry model calls itself, so set retries, fallbacks and
timeouts in the gateway.

**4. Check it.** Start a chat in Autoheal, then look for the calls in the
agents-py logs. Each line should name the gateway address, not the provider:

```bash
kubectl logs -n autoheal deploy/agents-py-worker --since=10m | grep 'HTTP Request: POST'
```

To turn the gateway off, set `enabled: false`, set `TF_VAR_llm_api_key` if your
provider uses a key, then apply `prod/infra` and `prod/app`.

The chart's `docs/prerequisites.md` ("LLM gateway") is the full reference.
`helm pull oci://public.ecr.aws/e4h3h0d9/charts/autoheal --version <version>`
downloads the chart with its docs.

---

## AWS / EKS

The same two folders as on Azure, from `examples/aws`. The infra folder creates
the VPC, EKS, Aurora PostgreSQL, ElastiCache, the S3 buckets, the KMS keys, the
Secrets Manager entries, the Pod Identity roles, the NLBs and the Route 53
records, or reads the ones you bring.

### Step 1: Sign in to AWS

```bash
aws sso login --profile <profile>     # or any other way to get credentials
export AWS_PROFILE=<profile>
aws sts get-caller-identity           # check it is the install account
```

The identity that runs Terraform needs AdministratorAccess, or PowerUserAccess
plus the IAM rights to create roles, policies and instance profiles. When your
account requires a permissions boundary on new roles, set
`iam_permissions_boundary_arn`. With `create_pod_identity_associations = false`
an administrator creates the Pod Identity associations listed in the
`required_role_assignments` output instead.

For prod we recommend its own AWS account, IAM Identity Center for people and
an OIDC role for the pipeline that only the protected prod environment can
assume. "Who can use the cluster" in `examples/aws/README.md` shows the setup.

Pick a region where EKS, Aurora PostgreSQL and ElastiCache are all offered, and
check the On-Demand vCPU quota for the node group (default three `m7i.xlarge`).
A first apply takes roughly 30 minutes; EKS and Aurora are the slow parts.

### Step 2: Copy the example into your repository

```bash
git clone --branch v4.1.1 https://github.com/autohealai/autoheal-byoc-infra.git
mkdir acme-autoheal && cp -r autoheal-byoc-infra/examples/aws/. acme-autoheal/
cd acme-autoheal
```

### Step 3: Create the state bucket (one time)

Edit `root.hcl`: pick the bucket name (globally unique) and region. Then create
it:

```bash
../autoheal-byoc-infra/scripts/bootstrap-state-aws.sh \
  --bucket acme-autoheal-tfstate \
  --region us-west-2
```

The script is idempotent. It turns on versioning, default encryption and
TLS-only access, and blocks public access. `root.hcl` locks state with a lock
file in the bucket (`use_lockfile`), which needs Terraform or OpenTofu 1.10 or
later; no DynamoDB table is needed.

### Step 4: Fill in your settings

- `prod/versions.hcl`: the infra tag and the chart version.
- `prod/infra/terragrunt.hcl`: `namespace`, `environment`, `account_id`,
  `region`, `hostname`, `existing_dns_zone_id` (the Route 53 hosted zone that
  holds the hostname), `edge_mode` and `edge_exposure`, the `existing_*` ARNs
  (the table in `examples/aws/README.md`), sizing, who may use the cluster
  (`cluster_admin_sso_permission_sets` and `cluster_viewer_sso_permission_sets`
  for IAM Identity Center, `cluster_admin_principal_arns` and
  `cluster_viewer_principal_arns` for IAM roles), and from where:
  `api_server_authorized_ip_ranges` set to the public egress address of the
  machine that runs Terraform (or `private_cluster_enabled = true` when it runs
  inside the VPC).
- `edge_mode`: keep `loadbalancer` unless the cluster already runs an Ingress
  controller, a Gateway or Istio. It needs none of them; Terraform creates a
  Network Load Balancer for the proxy.
- Secrets, as environment variables, never in a file:

  ```bash
  export TF_VAR_llm_api_key="..."               # if your LLM provider uses a key; not with Bedrock or an LLM gateway
  export TF_VAR_postgres_admin_password="..."   # only with existing_postgres_arn
  export TF_VAR_redis_auth_token="..."          # only with existing_redis_arn (AUTH must be on)
  export TF_VAR_llm_gateway_api_key="..."       # only with an LLM gateway; see "Optional: an LLM gateway"
  ```

**Backup, high availability and encryption.** The defaults are production
settings: a NAT gateway per zone, Aurora with a writer and a reader in different
zones, 30-day backups and deletion protection, ElastiCache with a replica and
automatic failover, customer managed KMS keys with rotation on (one each for
EKS secrets, the data stores, S3, Secrets Manager and logs), and 365-day log
retention. For a throwaway install, turn off
`postgres_deletion_protection_enabled` and set `postgres_skip_final_snapshot`
and `s3_force_destroy`, so `destroy` can remove everything.

### Step 5: Plan and apply the infra folder

```bash
cd prod/infra
terragrunt plan
terragrunt apply
```

If the plan stops with an error, it names the input to change (a brought
cluster in another VPC, a database older than PostgreSQL 15, a hostname outside
the hosted zone, and so on).

### Step 6: Check the outputs

```bash
terragrunt output required_role_assignments   # empty when Terraform made the associations
terragrunt output required_dns_records        # empty when Terraform made the records
terragrunt output required_cluster_owner_actions  # empty unless you brought the cluster
terragrunt output -raw autoheal_values_yaml   # what the chart receives; no secrets
```

### Step 7: Install the application

Edit `prod/app/values-customer.yaml` (admin email, LLM, SSO, sizing). Do not set
`global.infra`; those values come from the infra folder.

With `provider: bedrock`, agents-py calls Bedrock as its Pod Identity role
(`bedrock_access_enabled = true` in the infra folder), so there is no key. The
model must be enabled for the account in the Bedrock console first. Then:

```bash
cd ../app
terragrunt plan
terragrunt apply
```

The app folder logs in to EKS with `aws eks get-token`, so your AWS identity
must be a cluster admin. It installs the AWS Load Balancer Controller first,
which registers the pods in the NLB target groups, then the chart. On a brought
cluster that already runs a controller, remove `aws_load_balancer_controller`
from `prod/app/terragrunt.hcl`.

To install with Helm or Flux instead of the app folder, see
`examples/aws/README.md`.

### Step 8: Check the cluster (optional)

```bash
aws eks update-kubeconfig --region <region> --name <name>
kubectl get pods -n autoheal
kubectl get targetgroupbindings -n autoheal
```

`<region>` and `<name>` are in `terragrunt output cluster` in `prod/infra`.

---

## Upgrading

Change the two numbers in `prod/versions.hcl`, then plan and apply `prod/infra`
and `prod/app` again. Read `CHANGELOG.md` first; upgrading from 1.x has its own
notes there, and upgrading from 3.x to 4.x applies `prod/app` first. An AWS install on the 1.x `aws-byoc` composition is not upgraded in
place: install 3.x next to it and move the data.

---

## Tearing it down

Destroy in the reverse order of creation, the app folder first:

```bash
cd prod/app   && terragrunt destroy
cd ../infra   && terragrunt destroy
```

Brought resources are only read, so destroy leaves them in place. It removes
what the infra folder created, including the vault entries it wrote to a
brought vault.

> **Azure Key Vault soft-delete.** The provider uses the azurerm default
> `purge_soft_delete_on_destroy = true`, so teardown behaves differently depending
> on whether purge protection is on:
>
> - **Purge protection off** (the default, `key_vault_purge_protection_enabled =
>   false`): `destroy` soft-deletes *and then purges* the vault, so the name is
>   freed immediately and you can re-install with the same name right away. (If a
>   purge ever doesn't complete, free it with
>   `az keyvault purge --name <vault-name>`.)
> - **Purge protection on** (`key_vault_purge_protection_enabled = true`): the
>   vault **cannot** be purged on destroy or manually; it is soft-deleted and the
>   name stays reserved for the full `key_vault_soft_delete_retention_days` window
>   (default 7, up to 90). Leave purge protection off for throwaway/`play` installs
>   for this reason.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `terragrunt init` fails with a backend error or 403 | the state storage account does not exist, the names do not match `root.hcl`, or you lack Storage Blob Data Contributor on it | run Step 3; a new grant can take a few minutes to apply |
| `apply` fails with `AuthorizationFailed` on a role assignment | the identity cannot write role assignments | grant Owner, or Contributor + User Access Administrator, or set `create_role_assignments = false` |
| the apply stops listing missing role grants | `create_role_assignments = false` and the grants are not made yet | make the grants in `required_role_assignments`, then apply again |
| `plan` errors with "No apply-time path" or "No runtime path" to the Blob account or Key Vault | the firewalls deny all with no path open | set `deployer_ip_ranges` and `private_endpoints_enabled = true` |
| `plan` errors that a hostname is not inside the zone | `hostname` is not under `existing_dns_zone_id` | fix the hostname, or set `create_dns_records = false` |
| the app folder fails to log in to the cluster | `kubelogin` missing, or the wrong login mode | install `kubelogin`; set `kubelogin_login_mode` to match how the pipeline signs in |
| a provider "not registered" error | first use of the subscription | run the `az provider register` loop |
| `prod/app` stops with "global.llm.gateway.apiKeyVaultEntry is required for gateway kind", or the `autoheal-secrets-sync` Job cannot mount `gateway-api-key` | the gateway kind needs a key and `TF_VAR_llm_gateway_api_key` is not set | set it, any value for Portkey OSS, and apply `prod/infra` again |
| with Portkey OSS the pods run but every chat fails | the `x-portkey-config` header is missing, so Portkey has no provider to call | set `TF_VAR_llm_gateway_extra_headers`, then apply `prod/infra` and `prod/app` |
| `prod/app` stops with "global.llm.embeddingModel ... would skip the gateway" | with the gateway on, the embedding model does not start with `azure-openai:` | set `global.llm.embeddingModel` to `azure-openai:<model the gateway routes>` |
| the agents-py logs say "AZURE_OPENAI_BASE_URL must target the Azure OpenAI v1 GA API" | `global.llm.endpoint` does not end in `/openai/v1/` | add `/openai/v1/` to the endpoint and apply `prod/app` again |
| AWS: `terragrunt init` fails with `NoSuchBucket` or `AccessDenied` | the state bucket does not exist, its name or region does not match `root.hcl`, or you cannot read it | run Step 3 of the AWS steps |
| AWS: `init` rejects `use_lockfile` | Terraform or OpenTofu older than 1.10 | upgrade, or replace `use_lockfile` with a `dynamodb_table` in `root.hcl` |
| AWS: the app folder cannot log in to the cluster | the `aws` CLI is missing, or your identity has no EKS access entry | install the CLI; add the identity to `cluster_admin_principal_arns` and apply `prod/infra` |
| AWS: the `autoheal-secrets-sync` Job or a pod fails to mount secrets with `AccessDeniedException` | the Pod Identity associations do not exist yet | run the commands in `required_role_assignments`, or set `create_pod_identity_associations = true` |
| AWS: `prod/app` times out and `kubectl get targetgroupbindings -n autoheal` shows errors | no AWS Load Balancer Controller, or its role cannot register targets in the target groups | keep `aws_load_balancer_controller = { enabled = true }`, or allow `RegisterTargets` on the target groups for the cluster's own controller |

---

## Notes

- `plan` is a safe dry run. Nothing exists until `apply`.
- State holds the generated secrets, so keep it in the encrypted remote backend
  from `root.hcl` and limit who can read it.
