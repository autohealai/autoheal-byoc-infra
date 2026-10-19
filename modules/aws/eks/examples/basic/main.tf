# EKS cluster on a fresh VPC with a KMS key for Kubernetes Secrets and logs.
# Doubles as the CI plan/validate fixture.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.9"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# null-label (environment = lifecycle, not region); the cluster is acme-play-autoheal
locals {
  label = {
    namespace   = "acme"
    environment = "play"
    name        = "autoheal"
  }
}

module "kms" {
  source = "../../../kms"

  namespace   = local.label.namespace
  environment = local.label.environment
  name        = local.label.name

  description             = "Autoheal acme-play EKS secrets and logs"
  cloudwatch_logs_enabled = true
}

module "vpc" {
  source = "../../../vpc"

  namespace   = local.label.namespace
  environment = local.label.environment
  name        = local.label.name

  cidr_block           = "10.40.0.0/16"
  availability_zones   = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnet_cidrs = ["10.40.0.0/19", "10.40.32.0/19", "10.40.64.0/19"]
  public_subnet_cidrs  = ["10.40.96.0/24", "10.40.97.0/24", "10.40.98.0/24"]
  cluster_name         = "acme-play-autoheal"
}

module "eks" {
  source = "../../"

  namespace   = local.label.namespace
  environment = local.label.environment
  name        = local.label.name

  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  secrets_kms_key_arn = module.kms.key_arn
  log_kms_key_arn     = module.kms.key_arn

  # Operator egress range (documentation prefix as a placeholder).
  public_access_cidrs = ["203.0.113.0/24"]

  access_entries = {
    platform-admins = {
      principal_arn = "arn:aws:iam::111122223333:role/acme-platform-admin"
    }
    autoheal-viewers = {
      principal_arn     = "arn:aws:iam::111122223333:role/acme-autoheal-viewer"
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
      access_scope_type = "namespace"
      namespaces        = ["autoheal"]
    }
  }
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}
