# autoheal-byoc-infra

Terraform and Terragrunt code for the infrastructure Autoheal runs on inside a
customer's own cloud (BYOC). Azure is on 2.x; AWS is still on the 1.x
composition; GCP is planned.

A deployment has two folders, each with its own state:

1. **infra**: a cloud composition (`compositions/azure`) creates the cloud
   resources, or reads the ones you already have, and outputs the chart's infra
   values (`autoheal_values`) and how to reach the cluster (`cluster`).
2. **app**: `compositions/app` installs the Autoheal chart with those values and
   your `values-customer.yaml`.

Customers run compositions, never individual modules.

## Layout

```
modules/            Building blocks, one concern each.
  azure/            VNet, AKS, PostgreSQL Flexible, Managed Redis, Blob, Key Vault,
                    ACR, DNS records, private endpoints, runner VMSS, identities.
  aws/              VPC, Aurora, ElastiCache, S3, EKS, runner ASG, IRSA.
compositions/       Full wiring, one per cloud, plus the app install.
  azure/            Create, bring or mix every Azure building block.
  app/              The chart, on any cloud (helm_release).
  aws-byoc/         1.x AWS composition; the runner is a separate apply.
examples/
  azure/            A deployment repository to copy: root.hcl, prod/infra, prod/app.
  aws-byoc/         1.x AWS starting config.
docs/               MODULE_STANDARD.md (contributor contract), getting-started.md.
scripts/            bootstrap-state-azure.sh (one-time state storage account).
```

## Quick start (Azure)

Copy `examples/azure` into a repository you own and follow its README, or
[docs/getting-started.md](docs/getting-started.md) step by step. Once the state
storage account exists:

```bash
cd prod/infra && terragrunt apply   # cloud resources, vault entries, DNS, runner
cd ../app     && terragrunt apply   # the chart
```

To send model calls through an LLM gateway you run, such as Portkey, see
"Optional: an LLM gateway" in
[docs/getting-started.md](docs/getting-started.md#optional-an-llm-gateway).

## Versioning

One semver version for the whole repo. Pin a release tag; the examples read it
from `versions.hcl`:

```hcl
source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure?ref=v2.2.0"
```

Upgrading from 1.x: see the upgrade notes in [CHANGELOG.md](CHANGELOG.md).
[docs/MODULE_STANDARD.md](docs/MODULE_STANDARD.md) is the contributor contract
(naming, provider pinning, docs, CI gates, the output contract).
