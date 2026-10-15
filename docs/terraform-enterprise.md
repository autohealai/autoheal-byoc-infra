# Running the infra in Terraform Enterprise — step by step

A beginner-friendly guide to running the `azure-byoc` composition from Terraform
Enterprise (also called HCP Terraform or Terraform Cloud) instead of from a
laptop. No prior Terraform Enterprise experience is assumed.

Terraform Enterprise is mostly a website. The only commands you run are on the
Azure side, to create the identity that Terraform Enterprise signs in as.
Everything else is done in the Terraform Enterprise web interface.

## Which composition to use

Pick one before you start. The Terraform Enterprise steps are identical for both;
only the working directory and the Terraform inputs differ.

- **`azure-byoc-connect` (connect mode)** — use this when you already run the
  cluster and the data services (AKS, PostgreSQL, Redis, Key Vault, ACR, Storage
  Account). The composition does not build them. It reads them, then creates only
  the application and ESO identities, their role assignments, and seeds secrets
  into the existing Key Vault. **This is the right choice when you provision your
  own infrastructure.**
- **`azure-byoc` (create mode)** — use this when you want the composition to
  build the whole stack (cluster, database, storage, registry, identities) from
  nothing.

Connect mode requires all of these to already exist, or the apply fails: AKS
cluster, PostgreSQL Flexible Server, Key Vault, Redis, ACR, Storage Account.

The steps below show both. Where they differ, the connect-mode values come first.

## What you end up with

A Terraform Enterprise workspace that:

- is connected to this repository,
- signs in to Azure with no stored password (OIDC / dynamic credentials),
- can Plan and Apply the Azure infrastructure from the web interface,
- keeps its state in Terraform Enterprise, locked and versioned.

## Before you start

You need:

- Access to your Terraform Enterprise organization. Ask your administrator for
  the **organization name**.
- The `az` command-line tool installed, and the ability to sign in to the target
  subscription.
- Rights in Azure to create an app registration and to assign roles. Owner on
  the subscription is enough.

## Compatibility note

This repository is compatible with Terraform Enterprise:

- The state backend is a partial `backend "azurerm" {}` block, so it is not tied
  to Azure storage and can be moved to Terraform Enterprise.
- `required_version = ">= 1.6"`, which Terraform Enterprise supports.
- The code is fully declarative. It contains no `local-exec`, `remote-exec`, or
  `null_resource`, so it runs on Terraform Enterprise remote workers.
- The provider holds no credentials. They come from workspace variables.

Verified on both `azure-byoc` and `azure-byoc-connect` with
`tofu init -backend=false` and `tofu validate` (both pass). A full apply against a
live organization was not run here; that needs your organization and credentials.

---

## Part A — Azure side (run these commands once)

You create one Azure identity. Terraform Enterprise signs in as this identity.
You give it the rights the code needs, then you let it sign in without a
password.

### Step 1 — Sign in to Azure

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

### Step 2 — Create the identity (an app registration)

```bash
az ad app create --display-name "tfe-autoheal-byoc"

APP_ID=$(az ad app list --display-name "tfe-autoheal-byoc" --query "[0].appId" -o tsv)
az ad sp create --id "$APP_ID"
echo "App (client) ID: $APP_ID"
```

Write down the App (client) ID. You need it later.

### Step 3 — Give the identity the rights the code needs

The code creates resources (needs Contributor) and assigns roles to the
application identities (needs User Access Administrator). Contributor alone
cannot create role assignments, so both are required.

```bash
SUB="/subscriptions/<SUBSCRIPTION_ID>"
az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "$SUB"
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" --scope "$SUB"
```

An alternative to the two roles above is a single Owner assignment.

### Step 4 — Let Terraform Enterprise sign in without a password (OIDC)

This links a Terraform Enterprise workspace to the Azure identity. You add two
links: one for the Plan phase and one for the Apply phase.

Replace `<ORG>`, `<PROJECT>`, and `<WORKSPACE>` with your Terraform Enterprise
names. The project is `Default Project` unless you created one. The workspace
name must match the one you create in Part B.

The issuer is `https://app.terraform.io` for the hosted service. For a
self-hosted Terraform Enterprise, use your own address, for example
`https://tfe.example.com`.

```bash
ISSUER="https://app.terraform.io"      # or your self-hosted Terraform Enterprise URL
ORG="<ORG>"
PROJECT="<PROJECT>"
WS="autoheal-avid-play"

# link for the Plan phase
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"tfe-${WS}-plan\",
  \"issuer\": \"${ISSUER}\",
  \"subject\": \"organization:${ORG}:project:${PROJECT}:workspace:${WS}:run_phase:plan\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"

# link for the Apply phase
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"tfe-${WS}-apply\",
  \"issuer\": \"${ISSUER}\",
  \"subject\": \"organization:${ORG}:project:${PROJECT}:workspace:${WS}:run_phase:apply\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"
```

### Step 5 — Note these three values for later

```bash
echo "ARM_CLIENT_ID (App ID):   $APP_ID"
az account show --query "{ARM_SUBSCRIPTION_ID:id, ARM_TENANT_ID:tenantId}" -o table
```

The Azure side is done.

---

## Part B — Terraform Enterprise side (do this in the web interface)

### Step 6 — Create a workspace

- Open Terraform Enterprise. Choose your organization.
- Click **New**, then **Workspace**.
- Choose the **Version control workflow**.
- Connect to this repository.
- Set the **Terraform Working Directory**:
  - connect mode: `compositions/azure-byoc-connect`
  - create mode: `compositions/azure-byoc`
- Name the workspace `autoheal-avid-play`. It must match `<WORKSPACE>` from
  Step 4.

### Step 7 — Add the Terraform inputs (what to build)

Open the workspace, then **Variables**, then **Add variable**. For each one,
choose the category **Terraform**.

### Connect mode (`azure-byoc-connect`)

You point the composition at the resources you already run. All of these are
required, and each must name a resource that already exists.

| Key | Example value |
| --- | --- |
| `subscription_id` | your subscription GUID |
| `location` | `centralus` |
| `resource_group_name` | the RG that holds the existing resources |
| `aks_cluster_name` | the existing AKS cluster name |
| `postgres_server_name` | the existing PostgreSQL Flexible Server name |
| `redis_cache_name` | the existing Azure Cache for Redis name |
| `key_vault_name` | the existing Key Vault name |
| `acr_name` | the existing Azure Container Registry name |
| `storage_account_name` | the existing Storage Account name |
| `namespace` | `avid` |
| `environment` | `play` |

Optional but common in connect mode:

| Key | Value | Why |
| --- | --- | --- |
| `seed_secrets_enabled` | `true` | seed `redis-host`/`redis-port`/`redis-password`, `postgres-host`, `postgres-user` into the existing Key Vault. Needs Key Vault Secrets Officer (the composition can grant it to the deployer). Set `false` if you manage your own secrets. |
| `postgres_admin_login` | the PG admin username | recorded as the `postgres-user` secret |
| `additional_secrets` | `{ postgres-password = "..." }` | the server password cannot be read back from the server, so pass it here (mark the variable **Sensitive**) |
| `grant_app_acr_pull` | `true` | only if the app pulls images directly; the kubelet identity usually covers pulls |

### Create mode (`azure-byoc`)

| Key | Example value | Required |
| --- | --- | --- |
| `namespace` | `avid` | yes |
| `environment` | `play` | yes |
| `subscription_id` | your subscription GUID | yes |
| `location` | `centralus` | yes |

For a real (non-playground) create-mode install, also set:

| Key | Recommended value | Why |
| --- | --- | --- |
| `private_endpoints_enabled` | `true` | private path for pods; avoids a two-stage IP flow |
| `postgres_sku_name` | a provisioned SKU, for example `GP_Standard_D2ds_v5` | BYOC policy is provisioned, not burstable |
| `storage_network_default_action` | `Deny` | lock the Blob firewall |
| `key_vault_network_default_action` | `Deny` | lock the Key Vault firewall |
| `admin_group_object_ids` | your Entra group object ID | managed-AAD cluster access; disables static local admin |

### Step 8 — Add the Azure sign-in (OIDC, no password)

Add these four. Choose the category **Environment variable**.

| Key | Value |
| --- | --- |
| `TFC_AZURE_PROVIDER_AUTH` | `true` |
| `TFC_AZURE_RUN_CLIENT_ID` | the App ID from Step 5 |
| `ARM_SUBSCRIPTION_ID` | your subscription GUID |
| `ARM_TENANT_ID` | your tenant GUID |

These four, together with the links from Step 4, let Terraform Enterprise sign
in to Azure with no stored secret.

### Step 9 — Point the state at Terraform Enterprise

A configuration cannot have both a `cloud` block and a `backend` block. For
Terraform Enterprise, replace the `backend "azurerm" {}` block in your
composition's `backend.tf` (`compositions/azure-byoc-connect/backend.tf` for
connect mode, or `compositions/azure-byoc/backend.tf` for create mode) with a
`cloud` block, on the branch the workspace reads.

OLD:

```hcl
terraform {
  backend "azurerm" {}
}
```

NEW:

```hcl
terraform {
  cloud {
    organization = "<ORG>"
    workspaces { name = "autoheal-avid-play" }
  }
}
```

Do not use the Terragrunt wrapper under Terraform Enterprise. Terraform
Enterprise does not run Terragrunt. Point the workspace at the composition
directly, as above, and supply the inputs as workspace variables.

### Step 10 — Run it

- In the workspace, click **Actions**, then **Start new run**, then **Plan**.
- Read the plan. It lists what will be created.
- If it looks right, click **Confirm & Apply**.
- Terraform Enterprise builds the infrastructure and stores the state for you.

### Step 11 — Get the outputs

Open the workspace **Outputs** tab. The application install (the Autoheal BYOC
Helm install) reads these.

Connect mode (`azure-byoc-connect`) emits: `cluster_name`, `resource_group_name`,
`kube_host`, `oidc_issuer_url`, `postgres_host`, `redis_endpoint`, `object_store`,
`blob_endpoint`, `secret_store_uri`, `registry`, `acr_id`, `runner_identity`,
`eso_identity_client_id`, `eso_tenant_id`, `eso_service_account`.

Create mode (`azure-byoc`) emits the same set plus `acr_name` and
`runner_subnet_id`, but does not emit `redis_endpoint`, because it runs Redis
in-cluster (shipped by the app Helm chart) rather than as a managed service.

---

## Adding another environment (for example prod)

Repeat Part B with a new workspace name, for example `autoheal-avid-prod`, with
prod values. Repeat Step 4 once more with that new workspace name so OIDC works
for it too. The code is the same; the state and blast radius are separate per
workspace.

## Permissions summary

The identity Terraform Enterprise uses needs:

- **Create mode (`azure-byoc`)**: on the subscription, Owner, or Contributor and
  User Access Administrator. It builds resources (Contributor) and assigns roles
  (User Access Administrator).
- **Connect mode (`azure-byoc-connect`)**: it does not build the data services,
  so the scope can be the resource group rather than the whole subscription. It
  still needs Contributor (to create the two identities) and User Access
  Administrator (to assign roles), plus Key Vault Secrets Officer when
  `seed_secrets_enabled = true` (the composition can grant this to the deployer).

In both modes the code creates role assignments. Contributor alone cannot create
role assignments, which is why User Access Administrator is necessary.
