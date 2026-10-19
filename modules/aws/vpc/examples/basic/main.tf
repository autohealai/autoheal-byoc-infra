# Three-zone VPC with all four subnet tiers, per-zone NAT and the endpoints an
# EKS cluster uses most. Doubles as the CI plan/validate fixture.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "vpc" {
  source = "../../"

  # null-label (environment = lifecycle, not region); gives acme-play-autoheal
  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  cidr_block         = "10.40.0.0/16"
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

  private_subnet_cidrs = ["10.40.0.0/19", "10.40.32.0/19", "10.40.64.0/19"]
  public_subnet_cidrs  = ["10.40.96.0/24", "10.40.97.0/24", "10.40.98.0/24"]
  data_subnet_cidrs    = ["10.40.100.0/24", "10.40.101.0/24", "10.40.102.0/24"]
  runner_subnet_cidrs  = ["10.40.104.0/22", "10.40.108.0/22", "10.40.112.0/22"]

  nat_gateway_mode = "per_az"
  cluster_name     = "acme-play-autoheal"

  interface_endpoints = ["ecr.api", "ecr.dkr", "sts", "logs"]
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Egress IPs."
  value       = module.vpc.nat_gateway_public_ips
}
