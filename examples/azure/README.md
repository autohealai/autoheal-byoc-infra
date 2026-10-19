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
```

Each folder has its own state file (`autoheal/prod/infra`, `autoheal/prod/app`).
For a second environment, copy `prod/` to `staging/` and change the inputs.

## Which resources you bring

`prod/infra/terragrunt.hcl` creates everything apart from the DNS zone. Each
building block takes an `existing_*` ID; uncomment the ones you already have.

| You bring | Set |
|-----------|-----|
| Nothing (we create the network, AKS, Postgres, Redis, storage, Key Vault) | `network_cidr` |
| Your network | `existing_network` (subnet IDs and two free addresses in the AKS subnet). Allow ports 7233 and 8083 on the Temporal address from the runner subnet only. |
| Your cluster, database, cache, storage or vaults | `existing_aks_cluster_id`, `existing_postgres_id`, `existing_redis_id`, `existing_storage_account_id`, `existing_key_vault_id`, `existing_runtime_key_vault_id` |
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
  --version 1.0.0-rc.7 -n autoheal --create-namespace \
  -f values-infra.yaml -f ../app/values-customer.yaml --atomic --wait --timeout 20m
```

`values-infra.yaml` holds names, addresses and client IDs, never a secret.
