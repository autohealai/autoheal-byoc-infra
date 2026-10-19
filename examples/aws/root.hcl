# Written once. Every folder below includes it, so each folder gets its own
# state file in the same bucket: autoheal/prod/infra, autoheal/prod/app, and so
# on.
#
# Create the bucket once, before the first run, with
# scripts/bootstrap-state-aws.sh from autoheal-byoc-infra. Terraform cannot
# create the bucket that holds its own state.
#
# generate writes backend.tf into each folder's working copy of the
# composition. The compositions ship without a backend.tf for this reason.
#
# use_lockfile locks state with an object next to it, so no DynamoDB table is
# needed. It needs Terraform or OpenTofu 1.10 or later; on older versions set
# dynamodb_table instead.

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "acme-autoheal-tfstate"
    region       = "us-west-2"
    key          = "autoheal/${path_relative_to_include()}/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
