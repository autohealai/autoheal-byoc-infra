# VPC flow logs to a CloudWatch log group the module owns, written through a
# dedicated IAM role that only the flow logs service in this account can assume.

locals {
  flow_logs_count = var.flow_logs_enabled ? 1 : 0

  # IAM role names are limited to 64 characters. Keep the suffix and replace the
  # tail of a long label id with a short hash so names stay unique.
  flow_logs_role_suffix = "-vpc-flow-logs"
  flow_logs_role_name = (
    length("${module.this.id}${local.flow_logs_role_suffix}") <= 64
    ? "${module.this.id}${local.flow_logs_role_suffix}"
    : "${substr(module.this.id, 0, 64 - length(local.flow_logs_role_suffix) - 9)}-${substr(sha1(module.this.id), 0, 8)}${local.flow_logs_role_suffix}"
  )
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = local.flow_logs_count

  name              = "/aws/vpc/${module.this.id}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.flow_logs_kms_key_arn != "" ? var.flow_logs_kms_key_arn : null

  tags = module.this.tags
}

resource "aws_iam_role" "flow_logs" {
  count = local.flow_logs_count

  name = local.flow_logs_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "VpcFlowLogsAssume"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike = {
          "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"
        }
      }
    }]
  })

  tags = module.this.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = local.flow_logs_count

  name = "write-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteFlowLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = [
          aws_cloudwatch_log_group.flow_logs[0].arn,
          "${aws_cloudwatch_log_group.flow_logs[0].arn}:*",
        ]
      },
      {
        # DescribeLogGroups is a list call and is authorized against every log
        # group in the account and region, not a single one.
        Sid      = "ListLogGroups"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
    ]
  })
}

resource "aws_flow_log" "this" {
  count = local.flow_logs_count

  vpc_id               = aws_vpc.this.id
  traffic_type         = var.flow_logs_traffic_type
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn         = aws_iam_role.flow_logs[0].arn

  tags = merge(module.this.tags, { Name = "${module.this.id}-flow-logs" })

  depends_on = [aws_iam_role_policy.flow_logs]
}
