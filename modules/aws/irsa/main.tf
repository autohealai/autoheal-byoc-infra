# IRSA role for the Autoheal app service account(s). Trusts the EKS cluster OIDC
# provider for the given Kubernetes service accounts and grants the app read access
# to its Secrets Manager prefix and S3 bucket(s). The role ARN is the cross-cloud
# `runner_identity`; the Azure analogue is modules/azure/workload-identity (UAMI +
# federated credential). Naming/tags via the null-label base (module.this).

locals {
  # EKS OIDC trust conditions key off the host portion of the issuer URL.
  oidc_host = replace(var.oidc_provider_url, "https://", "")

  s3_object_arns = [for arn in var.s3_bucket_arns : "${arn}/*"]
  has_inline     = length(var.secret_arns) > 0 || length(var.s3_bucket_arns) > 0
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [for sa in var.federated_service_accounts : "system:serviceaccount:${sa.namespace}:${sa.service_account}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = coalesce(var.role_name_override, "${module.this.id}-irsa")
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = module.this.tags
}

data "aws_iam_policy_document" "app" {
  count = local.has_inline ? 1 : 0

  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []
    content {
      sid       = "SecretsRead"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = var.secret_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.s3_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "S3ObjectAccess"
      effect    = "Allow"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      resources = local.s3_object_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.s3_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "S3BucketList"
      effect    = "Allow"
      actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
      resources = var.s3_bucket_arns
    }
  }
}

resource "aws_iam_policy" "app" {
  count = local.has_inline ? 1 : 0

  name        = "${module.this.id}-irsa-access"
  description = "Autoheal app access to its Secrets Manager prefix and S3 bucket(s)."
  policy      = data.aws_iam_policy_document.app[0].json
  tags        = module.this.tags
}

resource "aws_iam_role_policy_attachment" "app" {
  count = local.has_inline ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.app[0].arn
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each = toset(var.extra_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
