# autoheal-byoc-infra

Terraform and Terragrunt code for the infrastructure Autoheal runs on inside a
customer's own cloud (BYOC): Azure and AWS, with the same structure on both. GCP
is planned.

A deployment has two folders, each with its own state:

1. **infra**: a cloud composition (`compositions/azure` or `compositions/aws`) creates the cloud
   resources, or reads the ones you already have, and outputs the chart's infra
   values (`autoheal_values`) and how to reach the cluster (`cluster`).
2. **app**: `compositions/app` installs the Autoheal chart with those values and
   your `values-customer.yaml`.

For an AKS cluster you bring, a third folder runs between the two:
`compositions/azure-cluster` reads the cluster, federates the workload
identities to it and outputs `cluster` for the app folder. The infra folder then
needs no access to the cluster at all.

Customers run compositions, never individual modules.

## Layout

```
modules/            Building blocks, one concern each.
  azure/            VNet, AKS, PostgreSQL Flexible, Managed Redis, Blob, Key Vault,
                    ACR, DNS records, private endpoints, identities.
  aws/              VPC, EKS, Aurora, ElastiCache, S3, KMS, Secrets Manager, ECR,
                    Route 53 records, NLBs, Pod Identity roles.
compositions/       Full wiring, one per cloud, plus the app install.
  azure/            Create, bring or mix every Azure building block.
  azure-cluster/    For an AKS cluster you bring: read it, federate the identities.
  aws/              Create, bring or mix every AWS building block.
  app/              The chart, on any cloud (helm_release), and the AWS Load
                    Balancer Controller on EKS.
examples/
  azure/            A deployment repository to copy: root.hcl, prod/infra, prod/app.
  aws/              The same for AWS.
docs/               MODULE_STANDARD.md (contributor contract), getting-started.md.
scripts/            bootstrap-state-azure.sh and bootstrap-state-aws.sh (one-time
                    state storage account or bucket).
```

## Quick start

Copy `examples/azure` or `examples/aws` into a repository you own and follow its
README, or [docs/getting-started.md](docs/getting-started.md) step by step. Once
the state storage account or bucket exists:

```bash
cd prod/infra && terragrunt apply   # cloud resources, vault entries, DNS
cd ../app     && terragrunt apply   # the chart
```

To send model calls through an LLM gateway you run, such as Portkey, see
"Optional: an LLM gateway" in
[docs/getting-started.md](docs/getting-started.md#optional-an-llm-gateway).

## Versioning

One semver version for the whole repo. Pin a release tag; the examples read it
from `versions.hcl`:

```hcl
source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure?ref=v4.0.0"
```

Upgrading from 1.x or 3.x: see the upgrade notes in [CHANGELOG.md](CHANGELOG.md).
[docs/MODULE_STANDARD.md](docs/MODULE_STANDARD.md) is the contributor contract
(naming, provider pinning, docs, CI gates, the output contract).
