# EKS cluster on a fresh VPC. Doubles as the CI plan/validate fixture.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "vpc" {
  source = "../../../vpc"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"

  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
  cluster_name       = "avid-play-autoheal"
}

module "eks" {
  source = "../../"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"

  cluster_name       = "avid-play-autoheal"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}
