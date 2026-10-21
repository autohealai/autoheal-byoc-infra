# Enhanced Monitoring role. RDS assumes it to publish OS metrics to CloudWatch
# Logs (RDSOSMetrics). Created only when monitoring_interval > 0. The trust
# policy is limited to this account to avoid the confused deputy problem.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # IAM role names are limited to 64 characters.
  monitoring_role_name_full = "${local.cluster_identifier}-rds-monitoring"
  monitoring_role_name      = length(local.monitoring_role_name_full) <= 64 ? local.monitoring_role_name_full : "${trimsuffix(substr(local.monitoring_role_name_full, 0, 55), "-")}-${substr(sha1(local.monitoring_role_name_full), 0, 8)}"
}

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    sid     = "RDSEnhancedMonitoring"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = local.monitoring_role_name
  description        = "Enhanced Monitoring for Aurora cluster ${local.cluster_identifier}"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json

  tags = module.this.tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
