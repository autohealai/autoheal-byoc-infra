# Module standard

The contract every module and composition in this repo follows. New work that
does not meet this bar should not merge.

## 1. Repo shape: monorepo of modules + compositions

- `modules/<cloud>/<name>/` — one concern each, reusable, cloud-scoped.
- `compositions/<cloud>-byoc/` — wire modules into the full Autoheal stack.
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
name = module.this.id          # e.g. avid-prod-autoheal
tags = module.this.tags        # consistent tag map on every resource
```

The repo's `label_order` default (drop `stage`, below) lives in each module's
`label.tf`, keeping the vendored `context.tf` pristine.

Label semantics **as used in this repo** (a deliberate deviation from Cloud
Posse's defaults — document it, do not assume the upstream meaning):

| Label | Meaning here | Example |
|-------|--------------|---------|
| `namespace`   | customer / tenant     | `avid` |
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

`compositions/aws-byoc` and `compositions/azure-byoc` **must emit the same output
names** so the Autoheal app install is cloud-agnostic and GKE can drop in later:

| Output | Meaning |
|--------|---------|
| `cluster_name`     | AKS/EKS cluster name |
| `postgres_host`    | PostgreSQL FQDN |
| `redis_endpoint`   | Redis endpoint — AWS only. Azure `azure-byoc` runs Redis in-cluster (app Helm chart) and omits this; `azure-byoc-connect` still emits it for bring-your-own managed Redis. |
| `object_store`     | Blob container / S3 bucket |
| `secret_store_uri` | Key Vault URI / SM ARN prefix |
| `registry`         | ACR login server / ECR registry |
| `runner_identity`  | runner workload identity (client id / role arn) |

## 9. Secrets

- No secrets in variables or state. Secrets live in Key Vault / Secrets Manager.
- `detect-secrets` + `.secrets.baseline` in pre-commit.
- Outputs carrying anything sensitive are marked `sensitive`.

## 10. CI gates (every PR)

`fmt -check`, `validate`, `tflint`, security scan (trivy), docs check, and a
`plan` on each example. See `.github/workflows/ci.yml`.

## 11. Remote state

Compositions configure a `remote_state` backend (Azure Storage container /
S3 + DynamoDB lock). State is never laptop-local for a real install.

## 12. Versioning

One semver version for the repo. `vX.Y.Z` git tags; `CHANGELOG.md` (keep-a-changelog).

- MAJOR: breaking interface change (consumer must edit config).
- MINOR: backward-compatible capability.
- PATCH: bug fix, no interface change.

Consumers pin `?ref=vX.Y.Z`.
