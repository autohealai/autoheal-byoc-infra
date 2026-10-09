# Autoheal BYOC — AWS IRSA (app identity)

IAM Role for Service Accounts (IRSA) for the Autoheal app. Trusts the EKS cluster
OIDC provider for the given Kubernetes service accounts and grants the app read
access to its Secrets Manager prefix and S3 bucket(s). Annotate the app service
account with `eks.amazonaws.com/role-arn = <role_arn>` and it assumes this role
with no static credentials.

The role ARN is the cross-cloud `runner_identity`. The Azure analogue is
`modules/azure/workload-identity` (UAMI + federated credential). Naming and tags
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
| `oidc_provider_arn` / `oidc_provider_url` | EKS cluster OIDC provider | (required) |
| `federated_service_accounts` | k8s SAs allowed to assume the role | (required) |
| `secret_arns` | secret ARNs/wildcards the app may read | `[]` |
| `s3_bucket_arns` | bucket ARNs the app may read/write | `[]` |
| `extra_policy_arns` | additional policies to attach | `[]` |

### Key outputs

| Name | Description |
|------|-------------|
| `role_arn` | role ARN — maps to the contract `runner_identity` |
<!-- END_TF_DOCS -->
