# Minimal Valkey replication group: a primary and one replica in two availability
# zones, reachable from the EKS cluster security group. Doubles as the CI validate
# fixture. The IDs and ARNs below are placeholders; the composition passes the
# vpc, eks and kms module outputs instead.
#
# attributes = ["cache"] gives the group a distinct name (acme-play-autoheal-cache)
# from the other components sharing the same namespace/environment/name.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.58, < 7.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "cache" {
  source = "../../"

  # null-label (environment = lifecycle, not region); "cache" distinguishes the name
  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["cache"]

  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]

  kms_key_arn     = "arn:aws:kms:us-west-2:111122223333:key/00000000-0000-0000-0000-000000000000"
  log_kms_key_arn = "arn:aws:kms:us-west-2:111122223333:key/00000000-0000-0000-0000-000000000000"

  # The composition generates this and stores it in Secrets Manager; placeholder for the fixture.
  auth_token = "REPLACE-ME-IN-composition" # pragma: allowlist secret
}

output "primary_endpoint_address" {
  description = "Primary endpoint."
  value       = module.cache.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint."
  value       = module.cache.reader_endpoint_address
}

output "security_group_id" {
  description = "Cache security group."
  value       = module.cache.security_group_id
}
