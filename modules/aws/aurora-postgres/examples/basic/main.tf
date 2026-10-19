# Minimal Aurora PostgreSQL cluster: two db.r7g.large instances in the data
# subnets, reachable from the EKS cluster security group. Doubles as the CI
# validate fixture. The IDs and ARNs below are placeholders; the composition
# passes the vpc, eks and kms module outputs instead.
#
# attributes = ["db"] gives the cluster a distinct name (acme-play-autoheal-db)
# from the other components sharing the same namespace/environment/name.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.59, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "aurora" {
  source = "../../"

  # null-label (environment = lifecycle, not region); "db" distinguishes the name
  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["db"]

  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]

  kms_key_arn     = "arn:aws:kms:us-west-2:111122223333:key/00000000-0000-0000-0000-000000000000"
  log_kms_key_arn = "arn:aws:kms:us-west-2:111122223333:key/00000000-0000-0000-0000-000000000000"

  # The composition generates this and stores it in Secrets Manager; placeholder for the fixture.
  master_password = "REPLACE_ME_IN_composition" # pragma: allowlist secret
}

output "endpoint" {
  description = "Writer endpoint."
  value       = module.aurora.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint."
  value       = module.aurora.reader_endpoint
}

output "security_group_id" {
  description = "Cluster security group."
  value       = module.aurora.security_group_id
}
