# Minimal VPC across two AZs with EKS discovery tags. Doubles as the CI
# plan/validate fixture.

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
  source = "../../"

  # null-label (environment = lifecycle, not region)
  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  vpc_cidr           = "10.60.0.0/16"
  availability_zones = ["us-west-2a", "us-west-2b"]
  cluster_name       = "acme-play-autoheal"
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}
