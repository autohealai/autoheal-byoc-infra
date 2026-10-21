# Aurora PostgreSQL cluster: one writer plus readers, private, encrypted with the
# caller's KMS key, TLS required. The Azure analogue is
# modules/azure/postgres-flexible.
#
# The cluster is reachable only through its own security group (security-group.tf)
# from the allowed security groups and CIDRs. Storage, snapshots and Performance
# Insights use kms_key_arn. rds.force_ssl = 1 in the cluster parameter group
# rejects plain TCP connections. Exported logs go to log groups this module
# creates first, so it sets their retention and encryption rather than RDS
# creating them with no expiry.
#
# Engine version: "16.11" pins the minor version. AWS still applies automatic
# minor upgrades when auto_minor_version_upgrade is true; the provider (6.59 and
# later) then keeps the plan clean instead of planning a downgrade. Raise the pin
# after an upgrade to keep the configuration honest. A major only value ("16")
# lets AWS pick the default minor and never shows minor drift.
#
# Serverless v2: instance_class = "db.serverless" makes every instance a
# Serverless v2 instance sized by the cluster's scaling configuration. The
# scaling configuration is always set: AWS ignores it while all instances are
# provisioned, and rejects removing it while a db.serverless instance still uses
# it, so a gated block would make the switch back to provisioned fail.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

locals {
  # Instance identifiers append "-N" (up to "-16"), so the cluster identifier
  # stays within 60 of the 63 characters RDS allows. Longer IDs are cut and get a
  # short hash so two long names never collide.
  id                 = module.this.id
  cluster_identifier = length(local.id) <= 60 ? local.id : "${trimsuffix(substr(local.id, 0, 51), "-")}-${substr(sha1(local.id), 0, 8)}"

  major_version = split(".", var.engine_version)[0]
  family        = "aurora-postgresql${local.major_version}"

  # The API returns an empty storage type for Aurora Standard; the provider
  # treats "aurora" and "" as equal, and "aurora" lets an I/O-Optimized cluster
  # switch back.
  storage_type = var.storage_type == "" ? "aurora" : var.storage_type

  cluster_parameters = merge(
    {
      "rds.force_ssl"              = "1"
      "log_min_duration_statement" = "1000"
    },
    var.cluster_parameters,
  )

  performance_insights_retention_days = 7
}

resource "aws_db_subnet_group" "this" {
  name        = local.cluster_identifier
  description = "Aurora PostgreSQL ${local.cluster_identifier}"
  subnet_ids  = var.subnet_ids

  tags = module.this.tags
}

resource "aws_rds_cluster_parameter_group" "this" {
  # The family is part of the name, so a major upgrade creates the new group
  # before the old one is removed.
  name        = "${local.cluster_identifier}-${local.family}"
  family      = local.family
  description = "Aurora PostgreSQL cluster parameters for ${local.cluster_identifier}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = contains(var.cluster_parameters_pending_reboot, parameter.key) ? "pending-reboot" : "immediate"
    }
  }

  tags = module.this.tags

  lifecycle {
    create_before_destroy = true
  }
}

# RDS writes exported logs to /aws/rds/cluster/<cluster>/<type> and creates the
# group itself, with no expiry, if it does not exist yet.
resource "aws_cloudwatch_log_group" "this" {
  for_each = toset(var.enabled_cloudwatch_logs_exports)

  name              = "/aws/rds/cluster/${local.cluster_identifier}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn != "" ? var.log_kms_key_arn : null

  tags = module.this.tags
}

# The final snapshot name must not collide with one left by an earlier cluster of
# the same name, and must not change on every plan (no timestamp()).
resource "random_id" "final_snapshot" {
  byte_length = 4

  keepers = {
    cluster_identifier = local.cluster_identifier
  }
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = local.cluster_identifier

  engine                      = "aurora-postgresql"
  engine_version              = var.engine_version
  allow_major_version_upgrade = var.allow_major_version_upgrade
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  apply_immediately           = var.apply_immediately

  master_username = var.master_username
  master_password = var.master_password
  port            = var.port

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_arn
  storage_type                        = local.storage_type
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${local.cluster_identifier}-final-${random_id.final_snapshot.hex}"

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Used only by db.serverless instances; see the header comment.
  serverlessv2_scaling_configuration {
    min_capacity = var.serverless_min_capacity
    max_capacity = var.serverless_max_capacity
  }

  tags = module.this.tags

  depends_on = [aws_cloudwatch_log_group.this]

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", local.cluster_identifier))
      error_message = "The cluster identifier (module.this.id) must start with a letter and use only lowercase letters, digits and single hyphens. Check namespace, environment, name and attributes."
    }

    precondition {
      condition     = var.serverless_min_capacity <= var.serverless_max_capacity
      error_message = "serverless_min_capacity must not be greater than serverless_max_capacity."
    }
  }
}

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${local.cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id

  # engine_version is left to the cluster: setting it here as well makes every
  # minor upgrade show as drift on each instance.
  engine         = aws_rds_cluster.this.engine
  instance_class = var.instance_class

  availability_zone    = length(var.instance_availability_zones) > 0 ? element(var.instance_availability_zones, count.index) : null
  db_subnet_group_name = aws_db_subnet_group.this.name
  publicly_accessible  = false
  ca_cert_identifier   = var.ca_cert_identifier

  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  apply_immediately            = var.apply_immediately
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? local.performance_insights_retention_days : null

  tags = module.this.tags
}
