# One IAM role for EKS Pod Identity plus the associations that bind it to
# Kubernetes service accounts. Replaces the 1.x IRSA module: no OIDC provider,
# no service account annotations, and the trust policy does not change when a
# cluster is rebuilt with the same name.
#
# Trust: only the EKS Pod Identity service, on behalf of the named cluster in
# this account, may assume the role (aws:SourceAccount + aws:SourceArn).
#
# Every for_each is keyed by caller-chosen map keys or by namespace and service
# account names, never by ARNs, so plans are complete even when policy ARNs or
# documents come from the same apply.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  # IAM role names are limited to 64 characters. Replace the tail of a long
  # label id with a short hash so names stay unique.
  role_name = (
    length(module.this.id) <= 64
    ? module.this.id
    : "${substr(module.this.id, 0, 55)}-${substr(sha1(module.this.id), 0, 8)}"
  )

  cluster_arn = "arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"

  associations = var.association_enabled ? {
    for a in var.associations : "${a.namespace}/${a.service_account}" => a
  } : {}
}

resource "aws_iam_role" "this" {
  name                  = local.role_name
  path                  = var.role_path
  max_session_duration  = var.max_session_duration
  permissions_boundary  = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  force_detach_policies = true

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EksPodIdentityAssume"
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = local.cluster_arn }
      }
    }]
  })

  tags = module.this.tags
}

resource "aws_iam_role_policy" "this" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.managed_policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_eks_pod_identity_association" "this" {
  for_each = local.associations

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.this.arn

  tags = module.this.tags
}
