# Run the infra in Terraform Enterprise, step by step

This guide tells you how to run the Azure composition from Terraform Enterprise.
Terraform Enterprise is also called HCP Terraform or Terraform Cloud. You do not
need Terraform Enterprise experience to follow this guide.

Terraform Enterprise is mostly a website. You run commands only on the Azure
side. You use the commands to make the identity that Terraform Enterprise signs
in as. You do all other steps in the Terraform Enterprise website.

## Which resources you bring

There is one Azure composition, `compositions/azure`. It creates every building
block you do not bring. For each one you already run, you set its `existing_*`
input to the resource ID, and the composition only reads it:

| You bring | Set |
| --- | --- |
| Nothing | `network_cidr` (the composition creates the network, AKS, Postgres, Redis, storage, Key Vault and the registry) |
| Your network | `existing_network` (subnet IDs and a free address in the AKS subnet for the proxy) |
| Your resource group | `existing_resource_group_id` |
| Your cluster, database, cache, storage, vaults or registry | `existing_aks_cluster_id`, `existing_postgres_id`, `existing_redis_id`, `existing_storage_account_id`, `existing_key_vault_id`, `existing_runtime_key_vault_id`, `existing_acr_id` |
| Role grants made by your administrators | `create_role_assignments = false` |
| DNS records made by a person | `create_dns_records = false` |

A brought resource must exist before the run, except a brought cluster, which
this workspace never reads. Mixes that cannot work (for example a brought
cluster without its network) stop the plan with a message that says what to
change. `compositions/azure/README.md` lists every case. With a brought cluster
you also run `compositions/azure-cluster`, in a second workspace (Step 11).

For an AKS cluster in a different subscription, with public endpoints, follow
the "With Terraform Enterprise" parts of
[the runbook](azure-two-subscriptions-public-runbook.md). It uses this guide for
the workspace and the sign-in, and adds the steps on the cluster.

The Terraform Enterprise steps are the same whatever you bring. Only the inputs
in Step 7 are different.

## What you get

You get a Terraform Enterprise workspace. The workspace does these things:

- It connects to your copy of this repository.
- It signs in to Azure with no stored password. It uses OIDC.
- It runs Plan and Apply from the website.
- It keeps the state in Terraform Enterprise. The state is locked and versioned.

The state holds the passwords and keys that the composition generates and
writes to Key Vault. Terraform Enterprise encrypts state at rest. Limit who can
read the workspace state.

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

- The compositions have no `backend` block. Terraform Enterprise keeps the
  state in the workspace.
- The code sets `required_version = ">= 1.7"`. Set the workspace Terraform
  version to 1.7 or later.
- The code is fully declarative. It has no `local-exec`, no `remote-exec`, and no
  `null_resource`. It runs on the Terraform Enterprise remote workers.
- The provider holds no credentials. The credentials come from workspace
  variables.

We tested `compositions/azure` with `terraform init -backend=false`,
`terraform validate` and `terraform test`. We did not run it in a Terraform
Enterprise organization. That needs your organization and your credentials.

---

## Part A: Azure side (run these commands one time)

You make one Azure identity. Terraform Enterprise signs in as this identity. You
give the identity the rights that the code needs. Then you let the identity sign
in with no password.

### Step 1: Sign in to Azure

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

### Step 2: Make the identity (an app registration)

```bash
az ad app create --display-name "tfe-autoheal-byoc"

APP_ID=$(az ad app list --display-name "tfe-autoheal-byoc" --query "[0].appId" -o tsv)
az ad sp create --id "$APP_ID"
echo "App (client) ID: $APP_ID"
```

Record the App (client) ID. You need it later.

### Step 3: Give the identity the rights that the code needs

The code makes resources. For this, the identity needs Contributor. With
`create_role_assignments = true` (the default) the code also assigns roles to
the Autoheal identities. For this, the identity needs User Access Administrator.
Contributor cannot assign roles.

```bash
SUB="/subscriptions/<SUBSCRIPTION_ID>"
az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "$SUB"
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" --scope "$SUB"
```

A single Owner assignment is an alternative to the two roles above. With
`create_role_assignments = false`, skip User Access Administrator. See
[Permissions summary](#permissions-summary).

### Step 4: Let Terraform Enterprise sign in with no password (OIDC)

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
WS="autoheal-infra-prod"

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

### Step 5: Record these three values for later

```bash
echo "ARM_CLIENT_ID (App ID):   $APP_ID"
az account show --query "{ARM_SUBSCRIPTION_ID:id, ARM_TENANT_ID:tenantId}" -o table
```

The Azure side is complete.

---

## Part B: Terraform Enterprise side (do this in the website)

### Step 6: Make a workspace

- Open Terraform Enterprise. Choose your organization.
- Click **New**. Then click **Workspace**.
- Choose the **Version control workflow**.
- Connect to your copy of this repository (a fork or a mirror).
- Set the **Terraform Working Directory** to `compositions/azure`.
- Set the **VCS branch** to a branch of your copy that holds the release you
  install, for example a branch made from the `v4.0.0` tag. To upgrade, move
  that branch to the next tag.
- Name the workspace `autoheal-infra-prod`. The name must be the same as
  `<WORKSPACE>` in Step 4.

### Step 7: Add the Terraform inputs (what to build)

Open the workspace. Click **Variables**. Click **Add variable**. For each
variable, choose the category **Terraform**. For a list or an object, tick
**HCL**.

These variables are necessary in every case:

| Key | Example value |
| --- | --- |
| `namespace` | `acme` |
| `environment` | `prod` |
| `subscription_id` | your subscription GUID |
| `location` | `eastus2` |
| `hostname` | `autoheal.acme.example` |

These variables depend on your setup:

| Key | Value | When |
| --- | --- | --- |
| `existing_dns_zone_id` | the Azure DNS zone ID for `hostname` | When Terraform creates the DNS records (the default). The composition never creates a zone. |
| `create_dns_records` | `false` | When your DNS is not in Azure DNS. Create the records listed in the `required_dns_records` output. |
| `network_cidr` | `10.60.0.0/16` | When the composition creates the network. |
| `existing_network` | `{ aks_subnet_id = "...", ..., proxy_ip = "..." }` (HCL) | When you bring the network. |
| `existing_*_id` | the resource ID | For each resource you bring (see [Which resources you bring](#which-resources-you-bring)). |
| `deployer_ip_ranges` | the egress addresses of your Terraform Enterprise workers, for example `["203.0.113.10/32"]` (HCL) | When the composition creates the storage account or the vault. Their firewalls default to `Deny`, and Terraform writes the vault entries through them. For a test install, `storage_network_default_action` and `key_vault_network_default_action` set to `Allow` work instead. |
| `create_role_assignments` | `false` | When your administrators make the role grants. |
| `edge_mode` | `loadbalancer`, `gateway-api`, `istio`, `ingress` or `none` | When the edge is not the default `loadbalancer`. Set `edge_address` with the other modes. |

These variables are secrets. Tick **Sensitive** for each:

| Key | Vault entry | When |
| --- | --- | --- |
| `llm_api_key` | `llm-api-key` | When your LLM provider uses an API key and the chart's LLM gateway is off |
| `postgres_admin_password` | `postgres-admin-password` | Only with `existing_postgres_id`. For a server the composition creates, it generates the password. |
| `sso_client_secret` | `sso-client-secret` | When SSO is on |
| `tls_certificate` | `tls-certificate`, `tls-private-key` | When the edge serves your own certificate. HCL: `{ certificate = "<PEM chain>", private_key = "<PEM>" }` |
| `github_app_private_key` | `github-app-private-key` | When you connect a GitHub App. Paste the PEM; Terraform stores it base64-encoded. |
| `github_app_webhook_secret` | `github-app-webhook-secret` | When you connect a GitHub App |
| `llm_gateway_api_key` | `gateway-api-key` | When the chart's LLM gateway is on, with any kind except `custom`. For a gateway that ignores it, such as Portkey OSS, any value. |
| `llm_gateway_extra_headers` | `gateway-extra-headers` | When the gateway needs extra headers. A JSON object of strings, for example `{"x-portkey-config":"<config JSON>"}`. |

When a private CA signed your certificate, also set `edge_ca_certificate` (not
sensitive) to the CA's PEM certificate. It is stored as `edge-ca-certificate`.

For a production install, also set these variables:

| Key | Recommended value | Why |
| --- | --- | --- |
| `private_endpoints_enabled` | `true` | This gives the pods a private path to the data services. |
| `aks_node_size`, `aks_node_count`, `postgres_sku` | sizes for your load | The defaults (`Standard_D4s_v6` x 2, `GP_Standard_D2ds_v5`) suit a small install. |

`compositions/azure/variables.tf` documents every input.

### Step 8: Add the Azure sign-in (OIDC, no password)

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

### Step 9: State

With the Version control workflow you do not change the code. The compositions
have no `backend` block, and Terraform Enterprise keeps the state in the
workspace.

To run plans from your own machine against the workspace (the CLI-driven
workflow), add a `cloud` block in a file of your own, for example
`compositions/azure/cloud.tf` in your copy:

```hcl
terraform {
  cloud {
    organization = "<ORG>"
    workspaces { name = "autoheal-infra-prod" }
  }
}
```

Do not use the Terragrunt example in `examples/azure` with Terraform Enterprise.
Terraform Enterprise does not run Terragrunt. Point the workspace at the
composition directly. Supply the inputs as workspace variables.

### Step 10: Run it

- In the workspace, click **Actions**. Then click **Start new run**. Then click
  **Plan**.
- Read the plan. The plan lists what the run will create.
- Click **Confirm & Apply** if the plan is correct.
- Terraform Enterprise builds the infrastructure. It stores the state for you.

With `create_role_assignments = false`, the first apply stops at the role check,
because the Autoheal identities are made in that apply. Give the
`required_role_assignments` output to your administrators. When they have made
the grants, start a new run.

### Step 11: Get the outputs

Open the workspace **Outputs** tab:

| Output | Use |
| --- | --- |
| `autoheal_values` | The chart's infra values. `compositions/app` takes them as `infra_values`. |
| `autoheal_values_yaml` | The same values as YAML. Save it as `values-infra.yaml` for a Helm or Flux install. |
| `cluster` | The cluster name, resource group, endpoint and CA certificate. For a brought cluster the endpoint and CA certificate are empty; the cluster workspace below outputs them. |
| `federation` | For a brought cluster: the identities to federate. The cluster workspace below takes it. |
| `required_role_assignments` | Grants your administrators must make. Empty when `create_role_assignments = true`. |
| `required_dns_records` | DNS records a person must create. Empty when Terraform creates them. |
| `network` | The VNet and subnet IDs and the address space, for peering, firewall rules or a VPN. |

None of the outputs holds a secret.

With a brought cluster (`existing_aks_cluster_id`), make a second workspace on
`compositions/azure-cluster`, the same way as Steps 6 to 10. Set its `cluster`
and `federation` variables (HCL) to the outputs of the same names above. Its
identity needs Azure Kubernetes Service Cluster User Role on the cluster, which
the `required_cluster_owner_actions` output lists for the cluster owner. When it
is the same identity as this workspace's, it can already write the federated
credentials. The run reads the cluster, makes one federated credential per
chart service account, and outputs `cluster` with the endpoint and CA
certificate. Run it before installing the chart: without the credentials the
chart's pods cannot sign in to Key Vault.

### Step 12: Install the chart

The simplest path is Helm or Flux with `autoheal_values_yaml`:

```bash
helm upgrade --install autoheal oci://public.ecr.aws/e4h3h0d9/charts/autoheal \
  --version 1.0.0-rc.8 -n autoheal --create-namespace \
  -f values-infra.yaml -f values-customer.yaml --atomic --wait --timeout 20m
```

`examples/azure/README.md` describes `values-customer.yaml`. To send model
calls through an LLM gateway, see "Optional: an LLM gateway" in
[getting-started.md](getting-started.md#optional-an-llm-gateway).

You can also run `compositions/app` in a second workspace. It logs in to AKS
with `kubelogin`, which the hosted workers do not have, so it needs a Terraform
Enterprise agent with `kubelogin` installed. It also needs the `autoheal_values`
output of the infra workspace as its `infra_values` input, and the `cluster`
output of the infra workspace, or of the cluster workspace for a brought
cluster, as its `cluster` input. This repository does not ship that wiring.

---

## Add another environment (for example staging)

Do Part B again with a new workspace name. An example is
`autoheal-infra-staging`. Use the staging values. Do Step 4 again with the new
workspace name. This makes OIDC work for the new workspace. The code is the
same. The state is separate. The blast radius is separate.

## Permissions summary

The identity that Terraform Enterprise uses needs these rights:

- **`create_role_assignments = true` (the default).** Owner, or Contributor and
  User Access Administrator. The scope is the subscription, or every resource
  group the composition creates resources in or reads brought resources from.
  The code builds resources with Contributor and assigns roles with User Access
  Administrator.
- **`create_role_assignments = false`.** Contributor on the same scope. The code
  makes no role assignments. Your administrators make the grants in the
  `required_role_assignments` output, and the apply checks the workload grants.

With a brought Key Vault and `create_role_assignments = false`, the identity also
needs Key Vault Secrets Officer on that vault to write the entries. The vault
owner grants it.

With a brought cluster, the infra workspace needs no right on the cluster or its
subscription. The cluster workspace needs Azure Kubernetes Service Cluster User
Role on the cluster, and write on the federated credentials of the three
workload identities, which the infra workspace's identity has.
