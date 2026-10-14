# Installing the Autoheal infrastructure — step by step

A beginner-friendly guide to provisioning the cloud infrastructure Autoheal runs
on, inside your own AWS or Azure account (BYOC — "bring your own cloud"). Follow
it start to finish; no prior Terraform experience is assumed.

## What you end up with

One command set provisions a complete stack:

- a Kubernetes cluster (AKS on Azure, EKS on AWS),
- a managed PostgreSQL database,
- object storage (Azure Blob / AWS S3),
- a container registry (ACR / ECR),
- a secrets store (Key Vault / Secrets Manager),
- the cloud identities that wire them together,

plus a single file — `autoheal-infra-outputs.json` — that the application install
reads afterward.

**This does not install the Autoheal application itself.** That is a separate step
(a Helm chart) that consumes the outputs file — see
[Next: install the application](#next-install-the-application).

How it fits together: you run one **composition** for your cloud (`azure-byoc` or
`aws-byoc`). A composition wires all the individual pieces into one install, so
you never assemble modules by hand. You drive it with **Terragrunt**, a thin
wrapper around Terraform.

---

## Before you start

### 1. Pick your cloud

This guide has two tracks — [Azure / AKS](#azure--aks) and [AWS / EKS](#aws--eks).
They are the same shape; only the sign-in, the remote-state setup, and a couple of
inputs differ. Follow the one you need.

### 2. Install the command-line tools

| Tool | What it's for | Install |
|------|---------------|---------|
| Terraform (>= 1.6) | provisions the infrastructure | https://developer.hashicorp.com/terraform/install |
| Terragrunt | the wrapper this repo drives | https://terragrunt.gruntwork.io/docs/getting-started/install/ |
| `az` CLI (Azure track) | sign in to Azure | https://learn.microsoft.com/cli/azure/install-azure-cli |
| `aws` CLI (AWS track) | sign in to AWS | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |

Terraform is the tested, canonical CLI here. OpenTofu also works, but it resolves
providers from the OpenTofu registry and will regenerate `.terraform.lock.hcl` in
your copy on `init`.

Confirm they are on your PATH:

```bash
terraform version     # must be >= 1.6
terragrunt --version
az version            # Azure track   (AWS track: aws --version)
```

### 3. Make sure you have enough permission

You cannot provision infrastructure you are not allowed to create. Check this
*before* you start — a missing role fails the apply partway through and leaves a
half-built stack.

- **Azure.** The composition **creates the install resource group** and then
  **role assignments** inside it (the app and ESO identities get Key Vault / Blob
  roles; AKS gets AcrPull on the registry). Creating role assignments needs the
  permission `Microsoft.Authorization/roleAssignments/write`, which **Contributor
  alone does not have**. Because the resource group does not exist yet at apply
  time, the role must be held at **subscription scope**: your identity must be
  **Owner**, or **Contributor + User Access Administrator**, on the subscription.
  With plain Contributor, `plan` succeeds but `apply` fails midway with
  `AuthorizationFailed`.
  <br>(Advanced alternative: pre-create the resource group, grant the role there,
  set `resource_group_name` to it, and `terraform import` it before the first
  apply. This guide does not cover that path.)
- **AWS.** You need permission to create the VPC, EKS, Aurora, and IAM resources —
  an administrator or an equivalently scoped role.

### 4. Azure only — one-time subscription setup

Skip this on AWS.

**Register the resource providers** (once per subscription; harmless to re-run):

```bash
for ns in Microsoft.ContainerService Microsoft.DBforPostgreSQL \
          Microsoft.Storage Microsoft.KeyVault Microsoft.ContainerRegistry \
          Microsoft.Network Microsoft.ManagedIdentity; do
  az provider register --namespace "$ns"
done
```

**Pick a tested region and check quota.** The regions this repo tests are
`centralus`, `westus3`, and `northcentralus`; PostgreSQL Flexible and AKS zone
availability differ elsewhere, so prefer one of these (others may work but are
unverified). Make sure the subscription has enough **regional vCPU quota** for the
node pool (the default `Standard_D4s_v6` pool scales 2–4 nodes).

> **Heads-up on cost and time.** `apply` creates real, billable resources. A full
> first apply takes roughly **15–25 minutes** — the Kubernetes cluster is the slow
> part. Nothing is billed until you run `apply`; `plan` is free and creates
> nothing.

---

## Azure / AKS

### Step 1 — Sign in to Azure

```bash
az login
az account set --subscription "<subscription-id>"   # az account show --query id -o tsv
```

### Step 2 — Get the repo and pin a release

```bash
git clone https://github.com/autohealai/autoheal-byoc-infra.git
cd autoheal-byoc-infra
git checkout v1.3.0          # pin a released version; don't run main
```

### Step 3 — Make your own copy of the example

Never edit the example in place — copy it, so you can keep your settings and pull
repo updates cleanly:

```bash
cp -r examples/azure-byoc examples/azure-byoc-mine
cd examples/azure-byoc-mine
```

### Step 4 — Fill in your settings

Open `terragrunt.hcl` and edit the values marked `EDIT` / `REPLACE_ME`:

- `namespace` — your customer/tenant short name, e.g. `acme`. It becomes the first
  part of every resource name.
- `environment` — lifecycle, one of `stage` | `prod` | `play` (this is **not** the
  region).
- `location` — the Azure region, e.g. `centralus` (see step 4 above).
- `subscription_id` — from `az account show --query id -o tsv`.
- the `remote_state` block — `resource_group_name` and `storage_account_name` for
  where Terraform keeps its state. Pick names now; you create them in Step 5. The
  storage account name must be 3–24 lowercase letters/numbers and globally unique.

The example ships as a **playground** config: it opens the Blob and Key Vault
firewalls (`*_network_default_action = "Allow"`) so the copy-paste flow just
works. For a `stage`/`prod` install, follow the comment in the file to switch to
private endpoints instead.

### Step 5 — Create the remote-state backend (one time)

Terraform stores its state in an Azure Storage container, but it cannot create the
account that holds its *own* state (chicken-and-egg). Create it once with the
helper script. **The three names must match the `remote_state` block from Step 4.**

```bash
../../scripts/bootstrap-state-azure.sh \
  --subscription    "<subscription-id>" \
  --resource-group  rg-autoheal-tfstate \
  --storage-account stautohealtfstate \
  --location        centralus
```

The script is idempotent — re-running against an existing backend is a no-op.

### Step 6 — Initialize

```bash
terragrunt init
```

This downloads the providers and connects to the state backend from Step 5. (If
this fails with a backend error, you almost certainly skipped Step 5 or the names
don't match.)

### Step 7 — Preview the plan

```bash
terragrunt plan
```

**Nothing is created yet.** Read the summary at the bottom — it should report a
number of resources to *add* and `0 to change, 0 to destroy`. If `plan` errors
here, it is usually a reachability or permission precondition telling you exactly
what to fix.

### Step 8 — Apply

```bash
terragrunt apply
```

Review the plan once more and type `yes`. This provisions the full stack and takes
~15–25 minutes.

### Step 9 — Save the outputs

```bash
terragrunt output -json > autoheal-infra-outputs.json
```

Keep this file — the application install reads it. See
[What the outputs are for](#what-the-outputs-are-for).

### Step 10 — (Optional) sanity-check the cluster

```bash
az aks get-credentials --resource-group <rg> --name <cluster_name>
kubectl get nodes      # should list the node pool, all Ready
```

`<rg>` and `<cluster_name>` are in your outputs file (`resource_group_name`,
`cluster_name`).

---

## AWS / EKS

### Step 1 — Sign in to AWS

```bash
aws sso login --profile <profile>     # or: aws configure
export AWS_PROFILE=<profile>
```

### Step 2 — Get the repo and pin a release

```bash
git clone https://github.com/autohealai/autoheal-byoc-infra.git
cd autoheal-byoc-infra
git checkout v1.3.0
```

### Step 3 — Make your own copy of the example

```bash
cp -r examples/aws-byoc examples/aws-byoc-mine
cd examples/aws-byoc-mine
```

### Step 4 — Fill in your settings

Open `terragrunt.hcl` and edit the `EDIT`-marked values: `namespace`,
`environment`, `region`, `availability_zones` (match them to the region), and the
`remote_state` block (an S3 bucket and a DynamoDB lock table).

Create the state bucket and lock table once (or have your platform team do it), and
put their names in the `remote_state` block. Unlike Azure, there is no bootstrap
script — a bucket and a DynamoDB table are all that is needed.

### Step 5 — Init, plan, apply, save outputs

```bash
terragrunt init
terragrunt plan      # review; nothing created yet
terragrunt apply     # type yes
terragrunt output -json > autoheal-infra-outputs.json
```

---

## What the outputs are for

`autoheal-infra-outputs.json` carries `cluster_name`, `postgres_host`,
`redis_endpoint`, `object_store`, `secret_store_uri`, `registry`, and
`runner_identity`. The application install reads these; the names are identical on
AWS and Azure, so the install does not care which cloud it ran on.

> **`redis_endpoint` is AWS-only.** The `azure-byoc` composition runs Redis
> in-cluster (shipped by the app Helm chart) and does not emit it. If you bring
> your own managed Redis on Azure, use `azure-byoc-connect`, which still emits it.

The Azure composition also emits identity/wiring extras the app install needs:
`resource_group_name`, `oidc_issuer_url`, `acr_id`, `runner_subnet_id`, and the
ESO wiring (`eso_identity_client_id`, `eso_tenant_id`, `eso_service_account`).

---

## Next: install the application

Provisioning stops at a running cluster + data tier + identities. The Autoheal
application is installed separately, by the **Autoheal BYOC Helm install** (the
umbrella chart / `install-aks.sh`), which consumes `autoheal-infra-outputs.json`
to:

- point `kubectl`/Helm at `cluster_name` in `resource_group_name`;
- stamp the app ServiceAccounts with `runner_identity` (the workload-identity
  client id);
- wire the ESO `ClusterSecretStore` at `secret_store_uri` using
  `eso_identity_client_id` / `eso_tenant_id` / `eso_service_account`;
- pull images from `registry`.

See the Autoheal BYOC install guide for the chart values and the exact mapping.

---

## Stage 2: the runner

The runner is intentionally **not** part of the composition: it needs the Temporal
internal load-balancer address, which only exists *after* the application is
deployed. Once the app is up, apply the runner as a second stage (Azure uses
`modules/azure/runner-vmss`, AWS uses `modules/aws/runner-asg`). On Azure the
runner-vmss module takes:

- from the infra outputs: `resource_group_name`, `location` (your `location`
  input), `runner_subnet_id` → `subnet_id`, `acr_id`, and `acr_name`;
- from the app install: `temporal_host` (the Temporal internal-LB address), plus
  `runner_image` and `sandbox_image`;
- from you: `admin_ssh_public_key`.

See the install guide for the stage-2 wrapper that supplies these.

---

## Tearing it down

Destroy in the reverse order of creation — the runner stage-2 apply first (if you
ran it), then the main stack:

```bash
terragrunt destroy      # from the same examples/<your-copy> dir
```

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
>   vault **cannot** be purged on destroy or manually — it is soft-deleted and the
>   name stays reserved for the full `soft_delete_retention_days` (7) window. Leave
>   purge protection off for throwaway/`play` installs for this reason.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `terragrunt init` fails with a backend error | the Azure state backend doesn't exist, or the `remote_state` names don't match | run Step 5 (bootstrap-state-azure.sh); make the three names match `terragrunt.hcl` |
| `apply` fails midway with `AuthorizationFailed` | the apply identity lacks `roleAssignments/write` | grant Owner, or Contributor + User Access Administrator, at **subscription** scope (Before you start §3) |
| `plan` errors about "no apply-time / runtime path to Blob/Key Vault" | the firewalls are deny-all with no reachable path | for a playground, keep `*_network_default_action = "Allow"`; for stage/prod set `private_endpoints_enabled`/`deployer_ip_ranges` per the example comments |
| quota or zone errors during `apply` | region quota or AKS/PG zone availability | use a tested region (`centralus`/`westus3`/`northcentralus`) and raise vCPU quota |
| a provider "not registered" error (Azure) | first-time subscription | run the `az provider register` loop (Before you start §4) |

---

## Notes

- `plan` is a safe dry run. Nothing exists until `apply`.
- For a real install, state lives in a shared remote backend (configured in the
  example's `terragrunt.hcl`), never on a laptop.
