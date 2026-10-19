# Customer managed KMS key (symmetric, ENCRYPT_DECRYPT) with an alias and a key
# policy built from plain inputs. The Azure analogue is a Key Vault key.
#
# The key policy always starts with the root statement for the current account,
# so IAM policies in the account can grant use of the key and the account can
# never lock itself out. Optional statements follow: key administrators, key
# users (with grants limited to AWS resources), the CloudWatch Logs service for
# log groups in this account and region, and any extra statements from the
# caller. A statement is only added when its input is non-empty; the length of a
# list is known at plan time even when its elements (ARNs from the same apply)
# are not, so the policy can always be planned.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  alias_name = var.alias != "" ? var.alias : "alias/${module.this.id}"

  root_statement = {
    Sid       = "EnableIAMUserPermissions"
    Effect    = "Allow"
    Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
    Action    = "kms:*"
    Resource  = "*"
  }

  administrator_statement = {
    Sid       = "KeyAdministrators"
    Effect    = "Allow"
    Principal = { AWS = var.key_administrator_arns }
    Action = [
      "kms:CancelKeyDeletion",
      "kms:Create*",
      "kms:Delete*",
      "kms:Describe*",
      "kms:Disable*",
      "kms:Enable*",
      "kms:Get*",
      "kms:ImportKeyMaterial",
      "kms:List*",
      "kms:Put*",
      "kms:Revoke*",
      "kms:RotateKeyOnDemand",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:Update*",
    ]
    Resource = "*"
  }

  user_statements = [
    {
      Sid       = "KeyUsers"
      Effect    = "Allow"
      Principal = { AWS = var.key_user_arns }
      Action = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]
      Resource = "*"
    },
    {
      # Lets AWS services (EBS, RDS, Secrets Manager, ...) create grants on
      # behalf of a key user, and nothing else.
      Sid       = "KeyUsersGrantsForAwsResources"
      Effect    = "Allow"
      Principal = { AWS = var.key_user_arns }
      Action    = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
      Resource  = "*"
      Condition = { Bool = { "kms:GrantIsForAWSResource" = "true" } }
    },
  ]

  # CloudWatch Logs encrypts log groups through the regional service principal.
  # The encryption context condition limits it to log groups in this account
  # and region.
  cloudwatch_logs_statement = {
    Sid       = "CloudWatchLogs"
    Effect    = "Allow"
    Principal = { Service = "logs.${local.region}.${data.aws_partition.current.dns_suffix}" }
    Action = [
      "kms:Decrypt*",
      "kms:Describe*",
      "kms:Encrypt*",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    Resource = "*"
    Condition = {
      ArnLike = {
        "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${local.region}:${local.account_id}:*"
      }
    }
  }

  key_policy = jsonencode({
    Version = "2012-10-17"
    # The for/if filters keep each optional statement out of the policy when
    # its input is empty, without a conditional that would have to unify
    # statement objects of different shapes.
    Statement = concat(
      [local.root_statement],
      [for s in [local.administrator_statement] : s if length(var.key_administrator_arns) > 0],
      [for s in local.user_statements : s if length(var.key_user_arns) > 0],
      [for s in [local.cloudwatch_logs_statement] : s if var.cloudwatch_logs_enabled],
      var.additional_policy_statements,
    )
  })
}

resource "aws_kms_key" "this" {
  description              = var.description
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  deletion_window_in_days  = var.deletion_window_in_days
  enable_key_rotation      = var.enable_key_rotation
  rotation_period_in_days  = var.enable_key_rotation ? var.rotation_period_in_days : null
  policy                   = local.key_policy

  tags = module.this.tags
}

resource "aws_kms_alias" "this" {
  name          = local.alias_name
  target_key_id = aws_kms_key.this.key_id
}
