# Installing Autoheal on your own cloud, step by step

A guide to installing Autoheal inside your own Azure subscription (BYOC, "bring
your own cloud"): the cloud resources first, then the application. No prior
Terraform experience is assumed. AWS still uses the 1.x flow, at the end.

## What you end up with

Two folders in a repository you own, each with its own state:

- `prod/infra` creates the cloud resources, or reads the ones you already have:
  network, AKS cluster, PostgreSQL, Redis, storage, Key Vault, workload
  identities, the runner VMs, DNS records, and every secret the application
  reads, written to Key Vault.
- `prod/app` installs the Autoheal chart into the cluster with the values the
  infra folder outputs and your own `values-customer.yaml`.

You drive both with **Terragrunt**, a thin wrapper around Terraform, from your
laptop for a first try or from a pipeline for a real install.

---

## Before you start

### 1. Install the command-line tools

| Tool | What it is for | Install |
|------|----------------|---------|
| Terraform (1.7 or later) | creates the infrastructure | https://developer.hashicorp.com/terraform/install |
| Terragrunt | runs each folder with its backend and inputs | https://terragrunt.gruntwork.io/docs/getting-started/install/ |
| `az` CLI | signs in to Azure | https://learn.microsoft.com/cli/azure/install-azure-cli |
| `kubelogin` | logs in to AKS with Entra ID for the chart install | https://azure.github.io/kubelogin/install.html |

Terraform is the tested CLI. OpenTofu also works; it resolves providers from the
OpenTofu registry and regenerates `.terraform.lock.hcl` on `init`.

```bash
terraform version     # 1.7 or later
terragrunt --version
az version
kubelogin --version
```

### 2. Check your permissions

A missing role fails the apply part way through, so check first.

- With `create_role_assignments = true` (the default) Terraform makes every
  role grant itself, which needs `Microsoft.Authorization/roleAssignments/write`.
  Contributor alone does not have it. Your identity must be **Owner**, or
  **Contributor + User Access Administrator**, on the subscription.
- If your administrators make role grants, set `create_role_assignments = false`.
  Contributor is then enough. The `required_role_assignments` output lists the
  grants to make, and the apply stops until they exist.

### 3. One-time subscription setup

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
four `Standard_D4s_v6` nodes) and the runner VMs (one `Standard_D4s_v6`).

> **Cost and time.** `apply` creates billable resources. A first apply takes
> roughly 20 to 30 minutes; the cluster and Redis are the slow parts. `plan` is
> free and creates nothing.

### 4. Decide what you bring

The infra folder creates everything you do not name. For each building block
you already have, set its `existing_*` ID in `prod/infra/terragrunt.hcl`:

| You bring | Set |
|-----------|-----|
| Nothing | `network_cidr` (the range for the new network) |
| Your network | `existing_network`: the AKS, runner, Postgres and private endpoint subnet IDs, and two free addresses in the AKS subnet (`temporal_ip`, and `proxy_ip` in `loadbalancer` mode) |
| Your cluster, database, cache, storage or vaults | `existing_aks_cluster_id`, `existing_postgres_id`, `existing_redis_id`, `existing_storage_account_id`, `existing_key_vault_id`, `existing_runtime_key_vault_id` |

We never create a DNS zone. Set `existing_dns_zone_id` to the Azure DNS zone that
holds your hostname, or set `create_dns_records = false` and create the records
listed in the `required_dns_records` output yourself.

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
git clone --branch v2.1.1 https://github.com/autohealai/autoheal-byoc-infra.git
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
  and it needs outbound access to the provider. For a cluster without internet
  access, mirror its image into your registry. Portkey OSS is the
  `portkeyai/gateway` image and listens on port 8787.

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

## AWS / EKS (1.x)

AWS still uses the 1.x composition `aws-byoc`, which creates the cluster and
data tier and outputs the 1.x contract. Pin a 1.x tag for it.

### Step 1: Sign in to AWS

```bash
aws sso login --profile <profile>     # or: aws configure
export AWS_PROFILE=<profile>
```

### Step 2: Get the repo and pin a release

```bash
git clone https://github.com/autohealai/autoheal-byoc-infra.git
cd autoheal-byoc-infra
git checkout v1.4.0   # the last 1.x release
```

### Step 3: Make your own copy of the example

```bash
cp -r examples/aws-byoc examples/aws-byoc-mine
cd examples/aws-byoc-mine
```

### Step 4: Fill in your settings

Open `terragrunt.hcl` and edit the `EDIT`-marked values: `namespace`,
`environment`, `region`, `availability_zones` (match them to the region), and the
`remote_state` block (an S3 bucket and a DynamoDB lock table).

Create the state bucket and lock table once (or have your platform team do it), and
put their names in the `remote_state` block. Unlike Azure, there is no bootstrap
script; a bucket and a DynamoDB table are all that is needed.

### Step 5: Init, plan, apply, save outputs

```bash
terragrunt init
terragrunt plan      # review; nothing created yet
terragrunt apply     # type yes
terragrunt output -json > autoheal-infra-outputs.json
```

---

## Upgrading

Change the two numbers in `prod/versions.hcl`, then plan and apply `prod/infra`
and `prod/app` again. Read `CHANGELOG.md` first; upgrading from 1.x has its own
notes there.

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

---

## Notes

- `plan` is a safe dry run. Nothing exists until `apply`.
- State holds the generated secrets, so keep it in the encrypted remote backend
  from `root.hcl` and limit who can read it.
