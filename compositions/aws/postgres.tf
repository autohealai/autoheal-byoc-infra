# PostgreSQL: the Aurora PostgreSQL cluster we create, or the customer's Aurora
# cluster or RDS for PostgreSQL instance read through a data source.
#
# We create the cluster in the data subnets with one writer and readers in
# other zones, storage and Performance Insights encrypted with the data key,
# TLS required (rds.force_ssl), automatic backups, deletion protection, a final
# snapshot and postgresql logs in CloudWatch. Only the node security group may
# connect. The chart's db-provision hook creates the databases and roles with
# the admin login; see secrets.tf.

module "postgres" {
  source = "../../modules/aws/aurora-postgres"
  count  = local.create_postgres ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["db"]
  tags        = var.tags

  vpc_id                     = local.vpc_id
  subnet_ids                 = local.data_subnet_ids
  allowed_security_group_ids = [local.node_security_group_id]

  engine_version          = var.postgres_engine_version
  instance_class          = var.postgres_instance_class
  instance_count          = var.postgres_instance_count
  serverless_min_capacity = var.postgres_serverless_min_capacity
  serverless_max_capacity = var.postgres_serverless_max_capacity
  storage_type            = var.postgres_storage_type

  master_username = var.postgres_admin_login
  master_password = local.postgres_admin_password
  kms_key_arn     = local.kms_key_arns.data

  backup_retention_period = var.postgres_backup_retention_days
  deletion_protection     = var.postgres_deletion_protection_enabled
  skip_final_snapshot     = var.postgres_skip_final_snapshot

  log_retention_days = var.log_retention_days
  log_kms_key_arn    = local.kms_key_arns.logs
}

# Generated when we create the cluster and no password is passed. Letters and
# digits only: RDS rejects /, @, " and spaces.
resource "random_password" "postgres_admin" {
  count   = local.create_postgres ? 1 : 0
  length  = 32
  special = false
}

locals {
  postgres_admin_password = var.postgres_admin_password != "" ? var.postgres_admin_password : try(random_password.postgres_admin[0].result, "")
}

data "aws_rds_cluster" "existing" {
  count              = local.postgres_brought_cluster ? 1 : 0
  cluster_identifier = local.existing.postgres.id
}

data "aws_db_instance" "existing" {
  count                  = !local.create_postgres && !local.postgres_brought_cluster ? 1 : 0
  db_instance_identifier = local.existing.postgres.id
}
