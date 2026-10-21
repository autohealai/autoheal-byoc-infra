# ElastiCache replication group (Valkey by default, Redis OSS supported), cluster
# mode disabled: one primary plus read replicas behind a primary and a reader
# endpoint. The Azure analogue is modules/azure/managed-redis.
#
# Clients must use TLS (transit encryption mode "required") and send the AUTH
# token. Data at rest, including snapshots, is encrypted with the caller's KMS
# key. Slow log and engine log go to CloudWatch log groups this module creates,
# so it sets their retention and encryption. The cache is reachable only through
# its own security group (security-group.tf).
#
# Naming and tags come from the null-label base (module.this); see label.tf.

locals {
  # Replication group IDs are limited to 40 characters. Longer IDs are cut and get
  # a short hash so two long names never collide.
  id                   = module.this.id
  replication_group_id = length(local.id) <= 40 ? local.id : "${trimsuffix(substr(local.id, 0, 31), "-")}-${substr(sha1(local.id), 0, 8)}"

  major_version = tonumber(split(".", var.engine_version)[0])

  # valkey8, valkey9, redis7; Redis OSS 6 uses the redis6.x family.
  family = var.engine == "valkey" ? "valkey${local.major_version}" : (local.major_version == 6 ? "redis6.x" : "redis${local.major_version}")

  # Parameter group names allow only letters, digits and hyphens.
  parameter_group_name = "${local.replication_group_id}-${replace(local.family, ".", "")}"

  log_types = ["slow-log", "engine-log"]
}

resource "aws_elasticache_subnet_group" "this" {
  name        = local.replication_group_id
  description = "Cache subnets for ${local.replication_group_id}"
  subnet_ids  = var.subnet_ids

  tags = module.this.tags
}

resource "aws_elasticache_parameter_group" "this" {
  # The family is part of the name, so a major upgrade creates the new group
  # before the old one is removed.
  name        = local.parameter_group_name
  family      = local.family
  description = "Parameters for ${local.replication_group_id}"

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = module.this.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = toset(local.log_types)

  name              = "/aws/elasticache/${local.replication_group_id}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn != "" ? var.log_kms_key_arn : null

  tags = module.this.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = local.replication_group_id
  description          = "Cache for ${local.id}"

  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = var.port
  parameter_group_name = aws_elasticache_parameter_group.this.name

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn

  auth_token                 = var.auth_token
  auth_token_update_strategy = var.auth_token_update_strategy

  snapshot_retention_limit   = var.snapshot_retention_limit
  snapshot_window            = var.snapshot_window
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  dynamic "log_delivery_configuration" {
    for_each = toset(local.log_types)
    content {
      destination      = aws_cloudwatch_log_group.this[log_delivery_configuration.value].name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = log_delivery_configuration.value
    }
  }

  tags = module.this.tags

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", local.replication_group_id))
      error_message = "The replication group ID (module.this.id) must start with a letter and use only lowercase letters, digits and single hyphens. Check namespace, environment, name and attributes."
    }

    precondition {
      condition     = (var.engine == "valkey" && local.major_version >= 7) || (var.engine == "redis" && local.major_version >= 6)
      error_message = "engine_version must be Valkey 7.2 or later, or Redis OSS 6.2 or later."
    }

    precondition {
      condition     = !var.multi_az_enabled || var.automatic_failover_enabled
      error_message = "multi_az_enabled needs automatic_failover_enabled = true."
    }

    precondition {
      condition     = !(var.multi_az_enabled || var.automatic_failover_enabled) || var.num_cache_clusters >= 2
      error_message = "multi_az_enabled and automatic_failover_enabled need num_cache_clusters >= 2. Set both to false for a single node."
    }
  }
}
