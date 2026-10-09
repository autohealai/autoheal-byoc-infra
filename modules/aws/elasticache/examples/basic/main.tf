# Minimal node-based ElastiCache Redis wired to a vpc module. Doubles as the CI
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
  source = "../../../vpc"

  namespace          = "avid"
  environment        = "play"
  name               = "autoheal"
  vpc_cidr           = "10.60.0.0/16"
  availability_zones = ["us-west-2a", "us-west-2b"]
  cluster_name       = "avid-play-autoheal"
}

module "redis" {
  source = "../../"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"
  attributes  = ["redis"]

  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr
  subnet_ids     = module.vpc.private_subnet_ids

  node_type          = "cache.t4g.small"
  num_cache_clusters = 2
}

output "redis_endpoint" {
  value = module.redis.endpoint
}
