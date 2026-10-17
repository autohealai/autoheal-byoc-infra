# Module standard

The contract every module and composition in this repo follows. New work that
does not meet this bar should not merge.

## 1. Repo shape: monorepo of modules + compositions

- `modules/<cloud>/<name>/` — one concern each, reusable, cloud-scoped.
- `compositions/<cloud>/`: wire modules into the Autoheal infrastructure for one
  cloud, for every case (create, bring, mixed). `compositions/aws-byoc` keeps its
  1.x name until it moves to this shape.
- `compositions/app/`: installs the chart on any cloud from the infra
  composition's outputs. The only composition with the `helm` and `kubernetes`
  providers.
- Consumers run compositions, never raw modules.

## 2. Naming and tagging: one shared label base

Naming and tagging go through a single shared base module, `modules/_shared/label`
— the equivalent of the Harness `harness-label` module. That base is the **only**
place Cloud Posse's `cloudposse/label/null` is pinned (currently `0.25.0`, in its
`context.tf`, copied verbatim — do not hand-edit it). Pinning it once means
upstream can never change under us, and a bump is a single reviewed edit.

Each module carries a slim, copyable `label.tf` that declares the label inputs
(`namespace`, `environment`, `name`, `attributes`, `tags`, `enabled`,
`label_order`, `context`) and forwards them to the base by relative path:

```hcl
module "this" {
  source      = "../../_shared/label"
  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = var.attributes
  tags        = var.tags
  label_order = var.label_order
  context     = var.context
}
```

The relative `source` means modules are versioned together with this repo — no
external pin at the consume site. Resources then derive all names and tags from it:

```hcl
name = module.this.id          # e.g. acme-prod-autoheal
tags = module.this.tags        # consistent tag map on every resource
```

The repo's `label_order` default (drop `stage`, below) lives in each module's
`label.tf`, keeping the vendored `context.tf` pristine.

Label semantics **as used in this repo** (a deliberate deviation from Cloud
Posse's defaults — document it, do not assume the upstream meaning):

| Label | Meaning here | Example |
|-------|--------------|---------|
| `namespace`   | customer / tenant     | `acme` |
| `environment` | **lifecycle** (not region) | `stage`, `prod`, `play` |
| `name`        | component             | `autoheal` |
| `attributes`  | extra qualifiers      | `["db"]` |

> Cloud Posse's own convention uses `environment` for the region and `stage` for
> lifecycle. We do **not** follow that. Here `environment` is the lifecycle and
> `stage` is dropped from `label_order`. Region is implied by the
> subscription/account; if ever multi-region in one account, add it as an
> `attribute`, never in `environment`.

Default `label_order = ["namespace", "environment", "name", "attributes"]`.

**Azure name sanitization.** Some Azure resources reject `-` and cap length
(Storage account, ACR: lowercase alphanumeric, <= 24). Modules for those resources
must transform `module.this.id` internally (strip delimiter, lowercase, truncate)
so consumers never think about it. See the Azure naming convention: `stautoheal<env>`,
`crautoheal<env>`.

## 3. Provider and version pinning

Every module has a `versions.tf` with `required_version` and `~>` provider
constraints. No unpinned providers.

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}
```

## 4. Lockfiles

- Commit `.terraform.lock.hcl` **only** in `compositions/` and `examples/` (roots).
- Never commit a lockfile inside a `modules/` directory — consumers resolve providers.
- Committed locks target the **Terraform registry** (the CI toolchain) and carry
  linux + darwin, amd64 + arm64 hashes — regenerate with
  `terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_amd64 -platform=darwin_arm64`.
  Terraform is canonical; OpenTofu consumers resolve from the OpenTofu registry and
  regenerate their own lock on `init`.

## 5. Generated docs

- `README.yaml` is the source; `README.md` is generated (terraform-docs).
- Inputs/outputs tables are never hand-maintained.
- Do not commit generator backup files (`*.backup.*`) — `.gitignore` them.

## 6. Examples as contract and fixtures

- Each module ships `examples/basic` (and `examples/complete` where useful).
- Each example is a runnable root and doubles as the CI plan fixture.

## 7. Variable and output hygiene

- Every variable: `type`, `description`, sane `default` where safe, `validation {}`
  where a bad value is catchable.
- Every output: `description`; mark `sensitive = true` for anything secret.

## 8. The output contract (cross-cloud)

Every 2.x infra composition emits the same output names, so `compositions/app`
and the chart do not care which cloud built the cluster:

| Output | Meaning |
|--------|---------|
| `autoheal_values`           | The chart's infra values as an object: `global.infra` facts, suggested `global.addons`, `global.secrets`, `global.edge`, and the Temporal and Zitadel copies. Shape versioned by `global.infra.version`. |
| `autoheal_values_yaml`      | The same values as YAML, for a Helm or Flux install. |
| `cluster`                   | `cloud`, `name`, `endpoint`, base64 `ca_certificate`, and `resource_group` (Azure) or `region` (AWS). No credential. |
| `required_role_assignments` | Grants an administrator must make when the composition makes none. |
| `required_dns_records`      | DNS records a person must create when the composition creates none. |
| `network`                   | The network Autoheal runs in. Azure: `vnet_id`, `vnet_name`, `resource_group_name`, `address_space`, `aks_subnet_id`, `runner_subnet_id`, `private_endpoint_subnet_id`. AWS will emit the VPC equivalents. |

None of them may hold a secret. Bump `global.infra.version` (the
`infra_contract_version` local) when the shape of `global.infra` changes.

`compositions/aws-byoc` still emits the 1.x contract (`cluster_name`,
`postgres_host`, `redis_endpoint`, `object_store`, `secret_store_uri`,
`registry`, `runner_identity`) until it moves to 2.x.

## 9. Secrets

- Secrets live in Key Vault / Secrets Manager. The compositions generate the
  install's secrets (database passwords, signing keys) and write them there in
  the same apply, so those values are in state: state must be in an encrypted,
  access-controlled backend (section 11).
- Secrets passed in (an LLM key, a brought server's admin password) are
  `sensitive` variables, set from the pipeline's secret store as `TF_VAR_*`,
  never in a committed file.
- No output carries a secret. Anything sensitive that must be output is marked
  `sensitive`.
- `detect-secrets` + `.secrets.baseline` in pre-commit.

## 10. CI gates (every PR)

`fmt -check`, `validate`, `tflint`, security scan (trivy), docs check, and a
`plan` on each example. See `.github/workflows/ci.yml`.

## 11. Remote state

State lives in a remote backend (Azure Storage container / S3 + DynamoDB lock),
never on a laptop for a real install. Compositions do not commit a `backend.tf`:
the caller generates it, for example with Terragrunt `remote_state` and
`generate` (`examples/azure/root.hcl`). That keeps `compositions/app` usable on
any cloud and lets Terragrunt write the file without a conflict.
`compositions/aws-byoc` keeps its 1.x partial `backend "s3" {}` block until it
moves to 2.x.

## 12. Versioning

One semver version for the repo. `vX.Y.Z` git tags; `CHANGELOG.md` (keep-a-changelog).

- MAJOR: breaking interface change (consumer must edit config).
- MINOR: backward-compatible capability.
- PATCH: bug fix, no interface change.

Consumers pin `?ref=vX.Y.Z`.
