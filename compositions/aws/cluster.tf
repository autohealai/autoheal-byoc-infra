# EKS: the cluster we create, or the customer's cluster read through a data
# source.
#
# We create a cluster with API authentication (access entries, no aws-auth
# ConfigMap), a private endpoint and an optional public one, Kubernetes Secrets
# encrypted with the eks key, every control plane log type in CloudWatch, and one
# managed node group in the private subnets. Nodes use IMDSv2 with a hop limit of
# 1, so pods cannot use the node role; workloads get AWS access through EKS Pod
# Identity (identity.tf). The add-ons include the Pod Identity agent and the
# Secrets Store CSI driver with the AWS provider, which the chart's secrets-sync
# hook uses to read Secrets Manager.
#
# There is no cluster autoscaler. The node group scales between eks_node_count
# and eks_node_max_count once one is installed (cluster-autoscaler or Karpenter).

module "eks" {
  source = "../../modules/aws/eks"
  count  = local.create_cluster ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  kubernetes_version = var.kubernetes_version
  vpc_id             = local.vpc_id
  subnet_ids         = local.private_subnet_ids

  endpoint_public_access = !var.private_cluster_enabled
  public_access_cidrs    = length(var.api_server_authorized_ip_ranges) > 0 ? var.api_server_authorized_ip_ranges : ["0.0.0.0/0"]

  secrets_kms_key_arn = local.kms_key_arns.eks
  log_retention_days  = var.log_retention_days
  log_kms_key_arn     = local.kms_key_arns.logs

  access_entries = { for arn in var.cluster_admin_principal_arns : arn => { principal_arn = arn } }

  node_instance_types = var.eks_node_instance_types
  node_capacity_type  = var.eks_node_capacity_type
  node_ami_type       = var.eks_node_ami_type
  node_min_size       = var.eks_node_count
  node_desired_size   = var.eks_node_count
  node_max_size       = max(var.eks_node_count, var.eks_node_max_count)
  node_disk_size_gb   = var.eks_node_disk_size_gb

  # The nodes pull the chart images through the ECR pull-through cache we create.
  node_additional_policy_arns = {
    for k, v in { "ecr-pull-through" = one(aws_iam_policy.ecr_pull_through[*].arn) } : k => v if local.create_registry
  }
}

data "aws_eks_cluster" "existing" {
  count = local.create_cluster ? 0 : 1
  name  = local.existing.eks.name
}
