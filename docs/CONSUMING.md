# Consuming autoheal-byoc-infra

How a customer provisions the Autoheal infrastructure. Pick your cloud; the flow
is identical apart from the auth step and the composition path.

## Prerequisites

- `terraform` (>= 1.6) and `terragrunt`. Terraform is the canonical, tested CLI —
  CI runs it and the committed composition locks target the Terraform registry.
  OpenTofu also works, but it resolves providers from the OpenTofu registry and will
  regenerate `.terraform.lock.hcl` in your working copy on `init`.
- Azure: `az` CLI. AWS: `aws` CLI.
- Permissions to create the resource group / account-level resources (see the
  install guide for the exact role set).

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

## Notes

- `plan` is a safe dry run. Nothing exists until `apply`.
- For a real install, state lives in a shared remote backend (configured in the
  example's `terragrunt.hcl`), never on a laptop.
