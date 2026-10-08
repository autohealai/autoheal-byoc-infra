# _shared/label

The repo's single naming and tagging base — the equivalent of the Harness
`harness-label` module. Every module in `modules/<cloud>/*` builds on this one,
so Cloud Posse's version is pinned in exactly one place.

- Wraps `cloudposse/label/null` pinned to **`0.25.0`** (see `context.tf`). Upstream
  cannot change under us; bumping the pin is a deliberate, reviewed edit here.
- Consuming modules reference it by relative path and are therefore versioned
  together with this repo:

  ```hcl
  module "this" {
    source = "../../_shared/label"

    namespace   = var.namespace
    environment = var.environment   # lifecycle (stage/prod/play), not region
    name        = var.name
    attributes  = var.attributes
    tags        = var.tags
    context     = var.context       # inheritance from the composition
  }
  ```

- Then: `name = module.this.id`, `tags = module.this.tags` on each resource.

Label semantics and the `environment = lifecycle` deviation are documented in
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md).
