# Consuming autoheal-byoc-infra

How a customer provisions the Autoheal infrastructure. Pick your cloud; the flow
is identical apart from the auth step and the composition path.

## Prerequisites

- `terraform` (>= 1.6) or `opentofu`, and `terragrunt`
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
# edit terragrunt.hcl: namespace, environment, location, subscription_id, resource_group

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

## Notes

- `plan` is a safe dry run. Nothing exists until `apply`.
- For a real install, state lives in a shared remote backend (configured in the
  example's `terragrunt.hcl`), never on a laptop.
