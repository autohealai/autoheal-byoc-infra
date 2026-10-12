# Copyable starting config for an AWS / EKS BYOC install.
#
#   cp -r examples/aws-byoc examples/aws-byoc-mine
#   cd examples/aws-byoc-mine
#   # edit the inputs + remote_state below
#   terragrunt init && terragrunt plan && terragrunt apply
#   terragrunt output -json > autoheal-infra-outputs.json
#
# After the app + Temporal are up, apply modules/aws/runner-asg separately, feeding
# it this stack's vpc_id + private_subnet_ids and the discovered internal NLB host.
#
# See docs/CONSUMING.md.

terraform {
  # Pin a release when consuming across repos; here we point at the composition in
  # this checkout.
  source = "${get_repo_root()}//compositions/aws-byoc"
}

# Remote state: one S3 bucket + DynamoDB lock table hold this install's state. Create
# them once (or have the install guide create them) and fill the values in.
# Terragrunt feeds these to the composition's partial `backend "s3"` block at init.
remote_state {
  backend = "s3"
  config = {
    bucket         = "autoheal-tfstate"              # EDIT: state bucket (globally unique)
    key            = "aws-byoc/terraform.tfstate"
    region         = "us-west-2"                     # EDIT: state bucket region
    dynamodb_table = "autoheal-tfstate-lock"         # EDIT: lock table
    encrypt        = true
  }
}

inputs = {
  # Identity / naming (environment = lifecycle, not region)
  namespace   = "avid"       # EDIT: customer / tenant
  environment = "play"       # EDIT: stage | prod | play
  name        = "autoheal"

  # Placement
  region             = "us-west-2"                               # EDIT
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"] # EDIT to match region

  # Optional knobs (defaults are sensible; uncomment to change)
  # vpc_cidr                     = "10.60.0.0/16"
  # kubernetes_version           = "1.34"
  # node_instance_types          = ["m7g.large"]
  # node_desired_size            = 3
  # postgres_instance_class      = "db.r7g.large"  # provisioned, NOT db.serverless
  # postgres_multi_az            = true
  # postgres_deletion_protection = false           # set true for stage/prod
  # redis_node_type              = "cache.m7g.large"
  # redis_num_cache_clusters     = 2

  # Set to match the Autoheal app install's Kubernetes service accounts.
  # federated_service_accounts = [
  #   { namespace = "app", service_account = "autoheal-app" },
  # ]
}
