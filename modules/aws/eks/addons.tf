# EKS managed add-ons. vpc-cni and eks-pod-identity-agent go on before the node
# group so the first nodes start with the final CNI settings and Pod Identity
# works from the start; the rest need running nodes and go on after it.
#
# A null version picks the default version EKS lists for kubernetes_version.

locals {
  addons_before_nodes = ["vpc-cni", "eks-pod-identity-agent"]

  ebs_csi_enabled = contains(keys(var.addons), "aws-ebs-csi-driver")
}

data "aws_eks_addon_version" "this" {
  for_each = var.addons

  addon_name         = each.key
  kubernetes_version = var.kubernetes_version
  most_recent        = false
}

resource "aws_eks_addon" "before_nodes" {
  for_each = { for name, addon in var.addons : name => addon if contains(local.addons_before_nodes, name) }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.version != null ? each.value.version : data.aws_eks_addon_version.this[each.key].version
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = module.this.tags
}

resource "aws_eks_addon" "after_nodes" {
  for_each = { for name, addon in var.addons : name => addon if !contains(local.addons_before_nodes, name) }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.version != null ? each.value.version : data.aws_eks_addon_version.this[each.key].version
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  dynamic "pod_identity_association" {
    for_each = each.key == "aws-ebs-csi-driver" ? [aws_iam_role.ebs_csi[0].arn] : []

    content {
      role_arn        = pod_identity_association.value
      service_account = "ebs-csi-controller-sa"
    }
  }

  tags = module.this.tags

  depends_on = [aws_eks_node_group.this]
}

# -----------------------------------------------------------------------------
# EBS CSI driver role, used through the add-on's Pod Identity association.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ebs_csi" {
  count = local.ebs_csi_enabled ? 1 : 0

  name = local.role_names.ebs_csi

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EksPodIdentityAssume"
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = aws_eks_cluster.this.arn }
      }
    }]
  })

  force_detach_policies = true

  tags = module.this.tags

  lifecycle {
    precondition {
      condition     = contains(keys(var.addons), "eks-pod-identity-agent")
      error_message = "aws-ebs-csi-driver gets its AWS credentials through Pod Identity, so addons must also include eks-pod-identity-agent."
    }
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = local.ebs_csi_enabled ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "${local.policy_prefix}/service-role/AmazonEBSCSIDriverPolicy"
}

# Needed only when volumes are encrypted with a customer managed key (a
# StorageClass kmsKeyId, or an account default EBS key that is a CMK).
resource "aws_iam_role_policy" "ebs_csi_kms" {
  count = local.ebs_csi_enabled && length(var.ebs_csi_kms_key_arns) > 0 ? 1 : 0

  name = "ebs-volume-encryption"
  role = aws_iam_role.ebs_csi[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GrantsForEbs"
        Effect   = "Allow"
        Action   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
        Resource = var.ebs_csi_kms_key_arns
        Condition = {
          Bool = { "kms:GrantIsForAWSResource" = "true" }
        }
      },
      {
        Sid      = "UseKeyForEbs"
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = var.ebs_csi_kms_key_arns
      },
    ]
  })
}
