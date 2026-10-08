# autoheal-byoc-infra

Terraform/Terragrunt modules and compositions to provision the infrastructure
Autoheal runs on inside a customer's own cloud (BYOC), across AWS and Azure
(GKE planned).

Consumers run a **composition** for their cloud, which provisions the full stack
and emits a fixed set of outputs that the Autoheal application install then
consumes. Consumers never wire individual modules themselves.

## Layout

```
modules/          Reusable building blocks, one concern each (the "ingredients").
  aws/            VPC, Aurora, ElastiCache, S3, EKS, runner ASG, IRSA.
  azure/          VNet, PostgreSQL Flexible, Redis Premium, Blob, Key Vault, ACR,
                  AKS, runner VMSS, workload identity.
  gcp/            Planned.
compositions/     Opinionated full-stack wiring, one per cloud (the "recipes").
  azure-byoc/     VNet + PG + Redis + Blob + KV + ACR + AKS + runner.
  aws-byoc/       VPC + Aurora + ElastiCache + S3 + EKS + runner.
examples/         Runnable, copyable starting configs per composition.
docs/             MODULE_STANDARD.md (contributor contract), CONSUMING.md (usage).
```

## Quick start

See [docs/CONSUMING.md](docs/CONSUMING.md). In short, from an example config:

```bash
terragrunt init
terragrunt plan      # review; nothing is created yet
terragrunt apply     # provision
terragrunt output -json > autoheal-infra-outputs.json   # feeds the app install
```

## Versioning

One semver version for the whole repo. Consumers pin a release tag:

```hcl
source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure-byoc?ref=v1.0.0"
```

See [docs/MODULE_STANDARD.md](docs/MODULE_STANDARD.md) for the full contributor
contract (naming, provider pinning, docs, CI gates, the output contract).
