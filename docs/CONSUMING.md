# Consuming autoheal-byoc-infra

How a customer provisions the Autoheal infrastructure. Pick your cloud; the flow
is identical apart from the auth step and the composition path.

## Prerequisites

- `terraform` (>= 1.6) or `opentofu`, and `terragrunt`
- Azure: `az` CLI. AWS: `aws` CLI.
- **Azure role set.** The composition creates **role assignments** (the app and
  ESO workload identities get Key Vault / Blob roles; AKS gets AcrPull on the
  registry). Writing role assignments needs
  `Microsoft.Authorization/roleAssignments/write`, which **Contributor does not
  have**. On the target subscription (or at least the install resource group and
  the registry) the apply identity must be **Owner**, or **Contributor + User
  Access Administrator**. With plain Contributor, `plan` succeeds and `apply`
  fails partway through with `AuthorizationFailed`, leaving a half-built stack.
- **Azure resource providers.** A first-time subscription must have the relevant
  providers registered (one-time, per subscription):
  ```bash
  for ns in Microsoft.ContainerService Microsoft.DBforPostgreSQL \
            Microsoft.Storage Microsoft.KeyVault Microsoft.ContainerRegistry \
            Microsoft.Network Microsoft.ManagedIdentity; do
    az provider register --namespace "$ns"
  done
  ```
- **Azure region + quota.** The regions this repo tests are `centralus`,
  `westus3`, and `northcentralus`; PG Flexible + AKS zone availability differ
  elsewhere, so prefer one of these (other regions may work but are unverified).
  Ensure the subscription has enough **regional vCPU quota** for the node pool
  (the default `Standard_D4s_v6` pool scales 2–4 nodes).
- AWS: permissions to create the VPC/EKS/Aurora/IAM resources (an admin or
  equivalently scoped role).

## Azure / AKS

```bash
az login
az account set --subscription "<subscription-id>"

git clone https://github.com/autohealai/autoheal-byoc-infra.git
cd autoheal-byoc-infra
git checkout v1.0.0                       # pin a release, don't run main

cp -r examples/azure-byoc examples/azure-byoc-mine
cd examples/azure-byoc-mine
# edit terragrunt.hcl: namespace, environment, location, subscription_id,
# and the remote_state resource_group_name / storage_account_name

# Step 0 — create the remote-state backend ONCE (Terraform can't create the
# account that holds its own state). Names must match the remote_state block above.
../../scripts/bootstrap-state-azure.sh \
  --subscription   "<subscription-id>" \
  --resource-group rg-autoheal-tfstate \
  --storage-account stautohealtfstate \
  --location       centralus

terragrunt init
terragrunt plan                           # review; nothing created yet
terragrunt apply                          # provisions the full stack
terragrunt output -json > autoheal-infra-outputs.json
```

## AWS / EKS

```bash
aws sso login --profile <profile>         # or aws configure
export AWS_PROFILE=<profile>

git clone https://github.com/autohealai/autoheal-byoc-infra.git
cd autoheal-byoc-infra
git checkout v1.0.0

cp -r examples/aws-byoc examples/aws-byoc-mine
cd examples/aws-byoc-mine
# edit terragrunt.hcl: namespace, environment, region

terragrunt init
terragrunt plan
terragrunt apply
terragrunt output -json > autoheal-infra-outputs.json
```

## What the outputs are for

`autoheal-infra-outputs.json` carries `cluster_name`, `postgres_host`,
`redis_endpoint`, `object_store`, `secret_store_uri`, `registry`, and
`runner_identity`. The Autoheal application install reads these; the output names
are identical on AWS and Azure, so the install does not care which cloud it ran on.

> Exception: `redis_endpoint` is AWS-only. The `azure-byoc` composition runs Redis
> in-cluster (shipped by the app Helm chart) and does not emit it. If you bring your
> own managed Redis on Azure, use `azure-byoc-connect`, which still emits it.

The Azure composition also emits identity/wiring extras the app install needs:
`resource_group_name`, `oidc_issuer_url`, `acr_id`, `runner_subnet_id`, and the
ESO wiring (`eso_identity_client_id`, `eso_tenant_id`, `eso_service_account`).

## Next: install the Autoheal application

Provisioning stops at a running cluster + data tier + identities. It does **not**
install the Autoheal application — that is a separate step that consumes
`autoheal-infra-outputs.json`. Hand the file to the **Autoheal BYOC Helm install**
(the umbrella chart / `install-aks.sh`), which uses these values to:

- point `kubectl`/Helm at `cluster_name` in `resource_group_name`;
- stamp the app ServiceAccounts with `runner_identity` (workload-identity client id);
- wire the ESO `ClusterSecretStore` at `secret_store_uri` using `eso_identity_client_id`
  / `eso_tenant_id` / `eso_service_account`;
- pull images from `registry`.

See the Autoheal BYOC install guide for the chart values and the exact mapping.

## Runner (stage 2)

The runner is intentionally **not** part of the composition: it needs the Temporal
internal load-balancer address, which only exists after the application is deployed.
Once the app is up, apply the runner as a second stage, feeding it the infra outputs
(`runner_subnet_id`, `acr_id`, `oidc_issuer_url`) plus the Temporal host — Azure uses
`modules/azure/runner-vmss`, AWS uses `modules/aws/runner-asg`. See the install guide
for the stage-2 wrapper.

## Teardown

Destroy in the reverse order of creation:

```bash
# 1. the runner stage-2 apply (if you ran it), then
terragrunt destroy     # from the same examples/<your-copy> dir
```

> **Azure Key Vault soft-delete.** Vaults are soft-deleted on destroy and the name
> is reserved during the retention window, so re-creating an install with the same
> `namespace`/`environment`/`name` fails until you purge the old vault:
> `az keyvault purge --name <vault-name>`. If `key_vault_purge_protection_enabled`
> was set, the vault **cannot** be purged early — it must age out the retention
> window — so leave purge protection off for throwaway/`play` installs.

## Notes

- `plan` is a safe dry run. Nothing exists until `apply`.
- For a real install, state lives in a shared remote backend (configured in the
  example's `terragrunt.hcl`), never on a laptop.
