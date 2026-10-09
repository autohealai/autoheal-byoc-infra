# Remote state backend. Configured at init time (partial config) by the Terragrunt
# wrapper in examples/aws-byoc, so the bucket / key / region / lock table are not
# hard-coded here. State never lives on a laptop for a real install
# (docs/MODULE_STANDARD.md §11).
terraform {
  backend "s3" {}
}
