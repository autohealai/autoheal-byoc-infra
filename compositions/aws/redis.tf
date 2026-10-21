# Redis: the ElastiCache for Valkey replication group we create, or the
# customer's replication group read through a data source. Off with
# redis_enabled = false.
#
# We create it in the data subnets, cluster mode disabled, with Multi-AZ
# automatic failover from two nodes, TLS in transit, encryption at rest with the
# data key, an AUTH token, daily snapshots and the slow and engine logs in
# CloudWatch. Only the node security group may connect. The chart connects with
# rediss:// and the token, both written to Secrets Manager in secrets.tf.

resource "random_password" "redis" {
  count   = local.create_redis ? 1 : 0
  length  = 64
  special = false
}

module "redis" {
  source = "../../modules/aws/elasticache"
  count  = local.create_redis ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["redis"]
  tags        = var.tags

  vpc_id                     = local.vpc_id
  subnet_ids                 = local.data_subnet_ids
  allowed_security_group_ids = [local.node_security_group_id]

  engine                     = "valkey"
  engine_version             = var.redis_engine_version
  node_type                  = var.redis_node_type
  num_cache_clusters         = var.redis_node_count
  multi_az_enabled           = var.redis_node_count >= 2
  automatic_failover_enabled = var.redis_node_count >= 2

  auth_token  = random_password.redis[0].result
  kms_key_arn = local.kms_key_arns.data

  log_retention_days = var.log_retention_days
  log_kms_key_arn    = local.kms_key_arns.logs
}

data "aws_elasticache_replication_group" "existing" {
  count                = var.existing_redis_arn != "" ? 1 : 0
  replication_group_id = local.existing.redis.id
}

locals {
  redis_auth_token = !local.redis_enabled ? "" : (
    local.create_redis ? random_password.redis[0].result : var.redis_auth_token
  )
}
