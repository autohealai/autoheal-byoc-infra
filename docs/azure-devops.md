# Run the install from Azure DevOps, step by step

This guide tells you how to install Autoheal on Azure from an Azure DevOps
pipeline with Terraform alone. You do not need Terragrunt. You use
`examples/azure/terraform`: two Terraform folders and a pipeline.

- `infra` makes the cloud resources with `compositions/azure`.
- `app` installs the chart with `compositions/app`. It reads the outputs of
  `infra` from its state file.
- `pipelines/azure-pipelines.yml` plans and applies `infra`, then `app`. Each
  apply waits for a person to approve it.

`examples/azure/terraform/README.md` says what each file does and how the
folders replace Terragrunt. `examples/azure/README.md` lists the inputs, what you
can bring and the secrets.

## What you get

- A pipeline with four stages: plan infra, apply infra, plan app, apply app.
- It signs in to Azure as a service connection with workload identity
  federation. No password or client secret is stored.
- The state is in an Azure storage account, one file per folder. The state is
  locked during a run and versioned.

The infra state holds the passwords and keys that the composition generates and
writes to Key Vault. Limit who can read the state storage account.

## Before you start

You need these items:

- An Azure DevOps project, and the rights to create service connections,
  variable groups, environments and agent pools in it.
- Rights in Azure to assign roles. Owner on the subscription is sufficient.
- The `az` command-line tool on your computer, to make the state storage
  account.
- A Git repository in the project for your copy of the example.

## Step 1: Agents

Use a self-hosted agent pool, not the Microsoft-hosted agents. The composition
puts firewalls on the storage account, the Key Vault and the AKS API. They allow
only the addresses you list, and Microsoft-hosted agents change address on every
run.

The agents need:

- A fixed public outbound address. List it in `deployer_ip_ranges` in
  `infra/main.tf`, and in `api_server_authorized_ip_ranges` if you restrict the
  AKS API. With `private_cluster_enabled = true`, the agents must be in a network
  that reaches the cluster's VNet and resolves its private DNS name instead.
- Terraform 1.11 or later. "Why Terraform 1.11" below says why.
- The `az` command-line tool, `bash` and `git`.
- Outbound HTTPS to `github.com` (the module source), `registry.terraform.io`
  and `releases.hashicorp.com` (the providers), `public.ecr.aws` (the chart, or
  your mirror) and Azure.

The app stages install `kubelogin` with the `KubeloginInstaller@0` task, which
downloads it from GitHub. If your agents have `kubelogin` already, remove that
task from `pipelines/terraform.yml`.

## Step 2: State storage account

Terraform cannot make the storage account that holds its own state. Make it once
with the script in this repository:

```bash
az login
./scripts/bootstrap-state-azure.sh \
  --subscription    <SUBSCRIPTION_ID> \
  --resource-group  rg-acme-tfstate \
  --storage-account stacmetfstate \
  --location        eastus2
```

You use the three names (resource group, storage account, container `tfstate`)
in Step 5.

## Step 3: Service connection

In the project, open Project settings, then Service connections. Make a new
**Azure Resource Manager** connection with **Workload identity federation**.
Name it `sc-autoheal-prod`, or change `serviceConnection` in
`azure-pipelines.yml`. Allow the pipeline to use it.

The connection signs in as an app registration or a managed identity. Its page
in Azure DevOps links to it. Give that identity these roles:

| Role | Scope | Why |
| --- | --- | --- |
| Contributor | the subscription, or every resource group the composition uses | makes the resources |
| User Access Administrator | the same scope | assigns roles to the Autoheal identities. Not needed with `create_role_assignments = false` |
| Storage Blob Data Contributor | the state storage account | reads and writes the state |

Owner on the scope replaces the first two. With `create_role_assignments =
false`, your administrators make the grants listed in the
`required_role_assignments` output instead. That list includes the grant that
lets the pipeline log in to the cluster for the app stages. With a brought AKS
cluster, the cluster owner also does the actions in the
`required_cluster_owner_actions` output. [terraform-enterprise.md](terraform-enterprise.md#permissions-summary)
lists the same rights in more detail.

```bash
SP=<OBJECT_ID_OF_THE_IDENTITY>
SUB="/subscriptions/<SUBSCRIPTION_ID>"
az role assignment create --assignee-object-id "$SP" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "$SUB"
az role assignment create --assignee-object-id "$SP" --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" --scope "$SUB"
az role assignment create --assignee-object-id "$SP" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$SUB/resourceGroups/rg-acme-tfstate/providers/Microsoft.Storage/storageAccounts/stacmetfstate"
```

## Step 4: Secrets

Make a variable group named `autoheal-prod-secrets` (Pipelines, Library). Link
it to a Key Vault you own, so the values stay in that vault. Add the secrets you
use, for example `llm-api-key`. Allow the pipeline to use the group.

This Key Vault is yours, for the pipeline. It is not the vault the composition
makes.

Each secret reaches Terraform through one line in the `env` block of
`pipelines/terraform.yml`:

```yaml
TF_VAR_llm_api_key: $(llm-api-key)
```

and a matching `variable` in `infra/variables.tf`, passed to the module in
`infra/main.tf`. Add one line for each secret you use and none for a secret you
do not set: Azure DevOps passes an undefined `$(name)` on as that literal text,
and Terraform would store it in Key Vault. `examples/azure/README.md` lists the
secrets.

## Step 5: Copy the example and fill in your values

Copy `examples/azure/terraform` into your repository. Then:

1. `infra/main.tf`: your inputs (names, subscription, region, network, sizing,
   hostname, `deployer_ip_ranges`).
2. `app/main.tf`: the state storage names in the `terraform_remote_state`
   block, and `create_namespace = false` if the cluster owner makes the
   namespace.
3. `app/values-customer.yaml`: your chart settings.
4. `pipelines/azure-pipelines.yml`: the pool, `autohealVersion`, the service
   connection, `rootFolder` (where `infra` and `app` are in your repository) and
   the state storage names.
5. Keep the `.terraform.lock.hcl` file in each folder. It pins the provider
   versions we test, so every run uses the same ones.

## Step 6: Approvals

Make an environment named `autoheal-prod` (Pipelines, Environments). Add an
**Approvals** check and pick the people who approve applies. Both apply stages
use this environment, so each one waits for an approval after its plan.

## Step 7: Make the pipeline and run it

Make a pipeline from the existing YAML file `pipelines/azure-pipelines.yml` in
your repository. It has `trigger: none`, so it runs only when someone starts it.

Run it. Read the infra plan, then approve the infra apply. Then read the app
plan and approve the app apply.

On the first run the app plan runs after the infra apply, because it needs the
cluster and the outputs. Read the `required_*` outputs at the end of the infra
apply: they list role grants, DNS records and cluster owner actions that a
person must do, and are empty when Terraform did them all.

Each apply stage plans again and applies that new plan, so approve soon after
the plan you read. To apply exactly the plan you approved, save it with
`terraform plan -out` and publish it as an artifact. The saved plan holds the
secrets, so protect it like the state.

## Why Terraform 1.11

The service connection hands out a sign-in token that lasts a few minutes. An
apply takes longer: the app stage waits up to 20 minutes for the chart. From
1.11, Terraform and its state backend ask Azure DevOps for a new token when the
old one expires. `pipelines/terraform.yml` turns this on with:

| Variable | Value |
| --- | --- |
| `ARM_CLIENT_ID`, `ARM_TENANT_ID` | from the `AzureCLI@2` task (`AZURESUBSCRIPTION_CLIENT_ID`, `AZURESUBSCRIPTION_TENANT_ID`) |
| `ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID` | the service connection ID (`AZURESUBSCRIPTION_SERVICE_CONNECTION_ID`) |
| `ARM_USE_OIDC` | `true` |
| `SYSTEM_ACCESSTOKEN`, `SYSTEM_OIDCREQUESTURI` | mapped from `$(System.AccessToken)` and `$(System.OidcRequestUri)`; Azure DevOps does not pass them to scripts by default |

The app stage logs in to AKS with `kubelogin_login_mode = "azurecli"`. The
`AzureCLI@2` task signs `az` in as the service connection, and `kubelogin` takes
the AKS token from `az` at the start of the plan. That token lasts about an
hour.

## Upgrading

Read the release notes in `CHANGELOG.md` first. Then change:

- the tag in the `source` lines of `infra/main.tf` and `app/main.tf`
  (`?ref=v3.0.0`);
- `autohealVersion` in `azure-pipelines.yml`.

Run `terraform init -upgrade` in each folder, commit the lock files, and run the
pipeline.

## Troubleshooting

| What you see | Cause | Fix |
| --- | --- | --- |
| `AADSTS700024: Client assertion is not within its valid time range` | Terraform older than 1.11, or `ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID` is not set | use Terraform 1.11 or later; keep the `export` lines in `terraform.yml` |
| `403` from the Key Vault or storage account during the infra apply | the agent's address is not in `deployer_ip_ranges` | add it and run the infra stages again |
| the app plan says `Unsupported attribute` on `data.terraform_remote_state.infra.outputs` | the infra folder has not been applied yet, or the state names in `app/main.tf` are wrong | apply infra first; check the names |
| the app plan cannot reach the cluster | the agent cannot reach the AKS API, or `kubelogin` is missing | check `api_server_authorized_ip_ranges` or the private network path; keep the `KubeloginInstaller@0` task |
| the plan wants to create everything on an install made with Terragrunt | the state addresses differ | see "Moving from the Terragrunt example" in `examples/azure/terraform/README.md` |
