# Run the infra in Terraform Enterprise — step by step

This guide tells you how to run the Azure composition from Terraform Enterprise.
Terraform Enterprise is also called HCP Terraform or Terraform Cloud. You do not
need Terraform Enterprise experience to follow this guide.

Terraform Enterprise is mostly a website. You run commands only on the Azure
side. You use the commands to make the identity that Terraform Enterprise signs
in as. You do all other steps in the Terraform Enterprise website.

## Which composition to use

Choose one composition before you start. The Terraform Enterprise steps are the
same for both. Only the working directory and the Terraform inputs are different.

- **`azure-byoc-connect` (connect mode).** Use this composition when you already
  run the cluster and the data services. These are the AKS cluster, PostgreSQL,
  Redis, Key Vault, ACR, and the Storage Account. The composition does not build
  these resources. It reads them. Then it makes only the application identity and
  the ESO identity. It assigns their roles. It also seeds secrets into the
  existing Key Vault. Use this composition when you provision your own
  infrastructure.
- **`azure-byoc` (create mode).** Use this composition when you want it to build
  the full stack. The full stack is the cluster, the database, the storage, the
  registry, and the identities.

Connect mode needs all of these resources before you start: the AKS cluster,
PostgreSQL, Redis, Key Vault, ACR, and the Storage Account. If one resource is
absent, the apply stops with an error.

The steps below show both modes. The connect-mode values come first.

## What you get

You get a Terraform Enterprise workspace. The workspace does these things:

- It connects to this repository.
- It signs in to Azure with no stored password. It uses OIDC.
- It runs Plan and Apply from the website.
- It keeps the state in Terraform Enterprise. The state is locked and versioned.

## Before you start

You need these items:

- Access to your Terraform Enterprise organization. Ask your administrator for
  the organization name.
- The `az` command-line tool. Install it. You must be able to sign in to the
  subscription.
- Rights in Azure to make an app registration and to assign roles. Owner on the
  subscription is sufficient.

## Compatibility

This repository is compatible with Terraform Enterprise. These are the reasons:

- The state backend is a partial `backend "azurerm" {}` block. The backend is
  not fixed. You can move the state to Terraform Enterprise.
- The code sets `required_version = ">= 1.6"`. Terraform Enterprise supports this
  version.
- The code is fully declarative. It has no `local-exec`, no `remote-exec`, and no
  `null_resource`. It runs on the Terraform Enterprise remote workers.
- The provider holds no credentials. The credentials come from workspace
  variables.

We tested the code on `azure-byoc` and `azure-byoc-connect`. We ran
`tofu init -backend=false` and `tofu validate`. Both commands passed. We did not
run a full apply. A full apply needs your organization and your credentials.

---

## Part A — Azure side (run these commands one time)

You make one Azure identity. Terraform Enterprise signs in as this identity. You
give the identity the rights that the code needs. Then you let the identity sign
in with no password.

### Step 1 — Sign in to Azure

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

### Step 2 — Make the identity (an app registration)

```bash
az ad app create --display-name "tfe-autoheal-byoc"

APP_ID=$(az ad app list --display-name "tfe-autoheal-byoc" --query "[0].appId" -o tsv)
az ad sp create --id "$APP_ID"
echo "App (client) ID: $APP_ID"
```

Record the App (client) ID. You need it later.

### Step 3 — Give the identity the rights that the code needs

The code makes resources. For this, the identity needs Contributor. The code also
assigns roles to the application identities. For this, the identity needs User
Access Administrator. Contributor cannot assign roles. Therefore you need both
roles.

```bash
SUB="/subscriptions/<SUBSCRIPTION_ID>"
az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "$SUB"
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" --scope "$SUB"
```

A single Owner assignment is an alternative to the two roles above.

### Step 4 — Let Terraform Enterprise sign in with no password (OIDC)

This step links a Terraform Enterprise workspace to the Azure identity. You add
two links. One link is for the Plan phase. One link is for the Apply phase.

Replace `<ORG>`, `<PROJECT>`, and `<WORKSPACE>` with your Terraform Enterprise
names. The project is `Default Project` if you did not make a project. The
workspace name must be the same as the name in Part B.

The issuer is `https://app.terraform.io` for the hosted service. For a
self-hosted Terraform Enterprise, use your own address. An example is
`https://tfe.example.com`.

```bash
ISSUER="https://app.terraform.io"      # or your self-hosted Terraform Enterprise URL
ORG="<ORG>"
PROJECT="<PROJECT>"
WS="autoheal-infra-play"

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

### Step 5 — Record these three values for later

```bash
echo "ARM_CLIENT_ID (App ID):   $APP_ID"
az account show --query "{ARM_SUBSCRIPTION_ID:id, ARM_TENANT_ID:tenantId}" -o table
```

The Azure side is complete.

---

## Part B — Terraform Enterprise side (do this in the website)

### Step 6 — Make a workspace

- Open Terraform Enterprise. Choose your organization.
- Click **New**. Then click **Workspace**.
- Choose the **Version control workflow**.
- Connect to this repository.
- Set the **Terraform Working Directory**:
  - connect mode: `compositions/azure-byoc-connect`
  - create mode: `compositions/azure-byoc`
- Name the workspace `autoheal-infra-play`. The name must be the same as
  `<WORKSPACE>` in Step 4.

### Step 7 — Add the Terraform inputs (what to build)

Open the workspace. Click **Variables**. Click **Add variable**. For each
variable, choose the category **Terraform**.

#### Connect mode (`azure-byoc-connect`)

You point the composition at the resources that you already run. All of these
variables are necessary. Each variable must name a resource that already exists.

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

These variables are optional. They are common in connect mode.

| Key | Value | Why |
| --- | --- | --- |
| `seed_secrets_enabled` | `true` | The composition seeds these secrets into the existing Key Vault: `redis-host`, `redis-port`, `redis-password`, `postgres-host`, and `postgres-user`. This needs Key Vault Secrets Officer. The composition can grant this role to the deployer. Set the value to `false` if you manage your own secrets. |
| `postgres_admin_login` | the PG admin username | The composition records this value as the `postgres-user` secret. |
| `additional_secrets` | `{ postgres-password = "..." }` | You cannot read the server password back from the server. Pass it here. Mark the variable **Sensitive**. |
| `grant_app_acr_pull` | `true` | Set this value to `true` only if the application pulls images directly. The kubelet identity usually pulls the images. |

#### Create mode (`azure-byoc`)

| Key | Example value | Necessary |
| --- | --- | --- |
| `namespace` | `avid` | yes |
| `environment` | `play` | yes |
| `subscription_id` | your subscription GUID | yes |
| `location` | `centralus` | yes |

For a real create-mode install, also set these variables. Do not use these for a
test install.

| Key | Recommended value | Why |
| --- | --- | --- |
| `private_endpoints_enabled` | `true` | This gives a private path for the pods. It also prevents a two-stage IP flow. |
| `postgres_sku_name` | a provisioned SKU, for example `GP_Standard_D2ds_v5` | The BYOC policy is provisioned. It is not burstable. |
| `storage_network_default_action` | `Deny` | This locks the Blob firewall. |
| `key_vault_network_default_action` | `Deny` | This locks the Key Vault firewall. |
| `admin_group_object_ids` | your Entra group object ID | This gives managed-AAD cluster access. It also disables the static local admin. |

### Step 8 — Add the Azure sign-in (OIDC, no password)

Add these four variables. For each variable, choose the category **Environment
variable**.

| Key | Value |
| --- | --- |
| `TFC_AZURE_PROVIDER_AUTH` | `true` |
| `TFC_AZURE_RUN_CLIENT_ID` | the App ID from Step 5 |
| `ARM_SUBSCRIPTION_ID` | your subscription GUID |
| `ARM_TENANT_ID` | your tenant GUID |

These four variables work with the links from Step 4. Together they let Terraform
Enterprise sign in to Azure with no stored secret.

### Step 9 — Point the state at Terraform Enterprise

A configuration cannot have a `cloud` block and a `backend` block at the same
time. For Terraform Enterprise, replace the `backend "azurerm" {}` block with a
`cloud` block. The block is in your composition's `backend.tf`. For connect mode,
this is `compositions/azure-byoc-connect/backend.tf`. For create mode, this is
`compositions/azure-byoc/backend.tf`. Make the change on the branch that the
workspace reads.

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
    workspaces { name = "autoheal-infra-play" }
  }
}
```

Do not use the Terragrunt wrapper with Terraform Enterprise. Terraform Enterprise
does not run Terragrunt. Point the workspace at the composition directly. Supply
the inputs as workspace variables.

### Step 10 — Run it

- In the workspace, click **Actions**. Then click **Start new run**. Then click
  **Plan**.
- Read the plan. The plan lists what the run will create.
- Click **Confirm & Apply** if the plan is correct.
- Terraform Enterprise builds the infrastructure. It stores the state for you.

### Step 11 — Get the outputs

Open the workspace **Outputs** tab. The application install reads these outputs.
The application install is the Autoheal BYOC Helm install.

Connect mode (`azure-byoc-connect`) emits these outputs: `cluster_name`,
`resource_group_name`, `kube_host`, `oidc_issuer_url`, `postgres_host`,
`redis_endpoint`, `object_store`, `blob_endpoint`, `secret_store_uri`,
`registry`, `acr_id`, `runner_identity`, `eso_identity_client_id`,
`eso_tenant_id`, and `eso_service_account`.

Create mode (`azure-byoc`) emits the same outputs. It also emits `acr_name` and
`runner_subnet_id`. It does not emit `redis_endpoint`. Create mode runs Redis in
the cluster. The app Helm chart ships Redis. Create mode does not use a managed
Redis service.

---

## Add another environment (for example prod)

Do Part B again with a new workspace name. An example is `autoheal-infra-prod`.
Use the prod values. Do Step 4 again with the new workspace name. This makes OIDC
work for the new workspace. The code is the same. The state is separate. The
blast radius is separate.

## Permissions summary

The identity that Terraform Enterprise uses needs these rights:

- **Create mode (`azure-byoc`).** On the subscription, the identity needs Owner.
  As an alternative, it needs Contributor and User Access Administrator. The code
  builds resources. For this, it needs Contributor. The code assigns roles. For
  this, it needs User Access Administrator.
- **Connect mode (`azure-byoc-connect`).** The composition does not build the
  data services. Therefore the scope can be the resource group, not the full
  subscription. The composition still needs Contributor. It uses Contributor to
  make the two identities. It also needs User Access Administrator. It uses User
  Access Administrator to assign the roles. It also needs Key Vault Secrets
  Officer when `seed_secrets_enabled = true`. The composition can grant this role
  to the deployer.

Both modes make role assignments. Contributor cannot make role assignments. This
is why User Access Administrator is necessary.
