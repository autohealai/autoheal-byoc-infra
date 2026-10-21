# EKS cluster for a BYOC Autoheal install: control plane, one managed node group
# and the EKS managed add-ons. The Azure analogue is modules/azure/aks.
#
#   - Authentication is EKS access entries only (authentication_mode = API). No
#     aws-auth ConfigMap and no IAM OIDC provider: workloads get AWS credentials
#     through EKS Pod Identity (modules/aws/pod-identity).
#   - Kubernetes Secrets are envelope-encrypted with the caller's KMS key.
#   - All control plane logs go to a log group the module creates first, so
#     retention and encryption apply from the first log line.
#
# Files: main.tf (cluster, cluster role, access entries), node_group.tf (node
# role, launch template, node group), addons.tf (add-ons and the EBS CSI role).
#
# Every count and for_each depends only on variables or map keys, so plans are
# complete even when ARNs passed in come from the same apply.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  cluster_name = module.this.id

  # IAM role names are limited to 64 characters. Keep the suffix and replace the
  # tail of a long label id with a short hash so names stay unique.
  role_suffixes = {
    cluster = "-eks-cluster"
    node    = "-eks-node"
    ebs_csi = "-eks-ebs-csi"
  }
  role_names = {
    for k, suffix in local.role_suffixes : k => (
      length("${module.this.id}${suffix}") <= 64
      ? "${module.this.id}${suffix}"
      : "${substr(module.this.id, 0, 64 - length(suffix) - 9)}-${substr(sha1(module.this.id), 0, 8)}${suffix}"
    )
  }

  policy_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"
}

# -----------------------------------------------------------------------------
# Cluster IAM role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = local.role_names.cluster

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EksControlPlaneAssume"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  force_detach_policies = true

  tags = module.this.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = {
    cluster_policy          = "${local.policy_prefix}/AmazonEKSClusterPolicy"
    vpc_resource_controller = "${local.policy_prefix}/AmazonEKSVPCResourceController"
  }

  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

# Lets the control plane use the secrets key for envelope encryption.
resource "aws_iam_role_policy" "cluster_secrets_kms" {
  name = "secrets-encryption"
  role = aws_iam_role.cluster.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SecretsEnvelopeEncryption"
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:ListGrants", "kms:DescribeKey"]
      Resource = var.secrets_kms_key_arn
    }]
  })
}

# -----------------------------------------------------------------------------
# Control plane log group. EKS writes to this exact name; creating it first
# means the module, not EKS, owns retention and encryption.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn != "" ? var.log_kms_key_arn : null

  tags = module.this.tags
}

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

# The public endpoint is on by default so an operator outside the VPC can run
# the install; callers lock it down with public_access_cidrs or turn it off.
#trivy:ignore:AVD-AWS-0040
#trivy:ignore:AVD-AWS-0041
resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  enabled_cluster_log_types = var.enabled_log_types
  deletion_protection       = var.deletion_protection

  # Keep the default aws-node, kube-proxy and CoreDNS that EKS installs at
  # creation. The managed add-ons in addons.tf take them over (OVERWRITE).
  # Without them the first nodes cannot reach the API server and never join.
  bootstrap_self_managed_addons = true

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = var.secrets_kms_key_arn
    }
  }

  upgrade_policy {
    support_type = var.upgrade_support_type
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    # EKS reports 0.0.0.0/0 when the public endpoint is off; matching it avoids
    # a permanent diff.
    public_access_cidrs = var.endpoint_public_access ? var.public_access_cidrs : ["0.0.0.0/0"]
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = var.service_ipv4_cidr != "" ? var.service_ipv4_cidr : null
  }

  tags = module.this.tags

  lifecycle {
    precondition {
      condition     = length(local.cluster_name) <= 100
      error_message = "The label id '${local.cluster_name}' is used as the cluster name and must be 100 characters or fewer."
    }

    postcondition {
      condition     = self.vpc_config[0].vpc_id == var.vpc_id
      error_message = "subnet_ids must belong to vpc_id (${var.vpc_id})."
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy.cluster_secrets_kms,
  ]
}

# -----------------------------------------------------------------------------
# Access entries. The node role entry is created by EKS for the managed node
# group; these are for people and automation.
# -----------------------------------------------------------------------------

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"

  tags = module.this.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.key].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope_type
    namespaces = each.value.access_scope_type == "namespace" ? each.value.namespaces : null
  }
}
