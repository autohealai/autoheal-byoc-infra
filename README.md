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
  azure/          VNet, PostgreSQL Flexible, Blob, Key Vault, ACR, AKS,
                  runner VMSS, workload identity. (No Redis: it runs in-cluster,
                  shipped by the app Helm chart — see azure-byoc.)
  gcp/            Planned.
compositions/     Opinionated full-stack wiring, one per cloud (the "recipes").
  azure-byoc/     VNet + PG + Blob + KV + ACR + AKS (Redis in-cluster). The runner
                  (runner-vmss) is a separate stage-2 apply — see getting-started.md.
  aws-byoc/       VPC + Aurora + ElastiCache + S3 + EKS. The runner (runner-asg) is
                  likewise a separate stage-2 apply.
examples/         Runnable, copyable starting configs per composition.
docs/             MODULE_STANDARD.md (contributor contract), getting-started.md (usage).
```

## Quick start

**New here? Follow [docs/getting-started.md](docs/getting-started.md) step by step.** It is a
beginner's tutorial that walks the whole install — install the tools, check your
permissions, sign in, copy an example, set up remote state, then
`init` → `plan` → `apply` — with a troubleshooting table at the end.

The core loop, once you have done the prerequisites and (on Azure) the one-time
state bootstrap, is:

```bash
terragrunt init
terragrunt plan      # review; nothing is created yet
terragrunt apply     # provision
terragrunt output -json > autoheal-infra-outputs.json   # feeds the app install
```

> This snippet is not a standalone runbook — on Azure it fails at `init` without
> the state backend. Follow getting-started.md end to end for a real install.

## Versioning

One semver version for the whole repo. Consumers pin a release tag:

```hcl
source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure-byoc?ref=v1.1.2"
```

See [docs/MODULE_STANDARD.md](docs/MODULE_STANDARD.md) for the full contributor
contract (naming, provider pinning, docs, CI gates, the output contract).
