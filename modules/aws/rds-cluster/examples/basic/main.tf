# Minimal provisioned Aurora PostgreSQL wired to a vpc module. Doubles as the CI
# plan/validate fixture. attributes = ["db"] gives a distinct identifier.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "vpc" {
  source = "../../../vpc"

  namespace          = "acme"
  environment        = "play"
  name               = "autoheal"
  vpc_cidr           = "10.60.0.0/16"
  availability_zones = ["us-west-2a", "us-west-2b"]
  cluster_name       = "acme-play-autoheal"
}

module "postgres" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["db"]

  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr
  subnet_ids     = module.vpc.private_subnet_ids

  # The composition generates this and seeds Secrets Manager; placeholder here.
  master_password = "REPLACE_ME_IN_composition" # pragma: allowlist secret
}

output "postgres_host" {
  value = module.postgres.host
}
