# Full AWS BYOC stack: wires the modules/aws/* building blocks into one install and
# emits the cross-cloud output contract. The Azure twin is compositions/azure-byoc.
#
# Scope: everything up to a running cluster + data tier + identities. One thing is
# deliberately NOT here:
#   - The runner ASG. It needs temporal_host (the internal NLB endpoint), which only
#     exists after the app + Temporal are deployed, so it is a separate apply after
#     the app install (feed-forward) via modules/aws/runner-asg, matching the Azure
#     runner unit. The vpc_id + private_subnet_ids outputs feed that step.

locals {
  cluster_name  = var.cluster_name != "" ? var.cluster_name : "${var.namespace}-${var.environment}-${var.name}"
  secret_prefix = var.secret_prefix != "" ? var.secret_prefix : "tenants/${var.namespace}"
}

# Admin password for Aurora PostgreSQL; seeded into Secrets Manager, never surfaced
# as a root output. The app reads it from Secrets Manager via IRSA.
resource "random_password" "postgres" {
  length           = 32
  special          = true
  override_special = "!#$%*-_=+"
}

module "vpc" {
  source = "../../modules/aws/vpc"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name

  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  cluster_name       = local.cluster_name
}

module "eks" {
  source = "../../modules/aws/eks"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}

module "rds" {
  source = "../../modules/aws/rds-cluster"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["db"]

  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr
  subnet_ids     = module.vpc.private_subnet_ids
  allowed_sg_ids = [module.eks.cluster_primary_security_group_id]

  engine_version      = var.postgres_engine_version
  instance_class      = var.postgres_instance_class
  multi_az            = var.postgres_multi_az
  master_password     = random_password.postgres.result
  deletion_protection = var.postgres_deletion_protection
}

module "elasticache" {
  source = "../../modules/aws/elasticache"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["redis"]

  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr
  subnet_ids     = module.vpc.private_subnet_ids
  allowed_sg_ids = [module.eks.cluster_primary_security_group_id]

  node_type          = var.redis_node_type
  num_cache_clusters = var.redis_num_cache_clusters
}

module "s3" {
  source = "../../modules/aws/s3"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["attachments"]
}

module "ecr" {
  source = "../../modules/aws/ecr"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name

  repository_names = var.ecr_repository_names
}

module "secrets" {
  source = "../../modules/aws/secrets-manager"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name

  secret_prefix = local.secret_prefix
  secrets = {
    "postgres-password" = random_password.postgres.result
    "postgres-host"     = module.rds.host
    "postgres-user"     = module.rds.administrator_login
    "redis-host"        = module.elasticache.primary_endpoint_address
    "redis-port"        = tostring(module.elasticache.port)
  }
}

module "irsa" {
  source = "../../modules/aws/irsa"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["app"]

  oidc_provider_arn          = module.eks.oidc_provider_arn
  oidc_provider_url          = module.eks.oidc_provider_url
  federated_service_accounts = var.federated_service_accounts

  secret_arns    = ["${module.secrets.secret_store_uri}/*"]
  s3_bucket_arns = [module.s3.bucket_arn]
}
