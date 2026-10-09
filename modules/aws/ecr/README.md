# Autoheal BYOC — AWS ECR

ECR repositories for a BYOC-on-EKS Autoheal install. ECR is an account-level
registry (`<account>.dkr.ecr.<region>.amazonaws.com`); this module creates the
per-service repositories under it and a lifecycle policy that prunes old images.
Nodes pull via the node-group role (wired in `modules/aws/eks`); the runner pulls
via its instance profile (`modules/aws/runner-asg`).

The Azure analogue is `modules/azure/acr` (one registry resource) — here the
"registry" is the account endpoint, exposed as `registry_url`. Naming and tags
follow the repo's null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     Module-specific inputs are in variables.tf; label inputs come from label.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `repository_names` | repositories to create | `[]` |
| `image_tag_mutability` | MUTABLE / IMMUTABLE | `MUTABLE` |
| `max_image_count` | tagged images to keep per repo | `100` |
| `untagged_image_days` | expire untagged after N days | `14` |

### Key outputs

| Name | Description |
|------|-------------|
| `registry_url` | account registry endpoint — maps to the contract `registry` |
| `repository_urls` | map of repo name -> URL |
<!-- END_TF_DOCS -->
