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

  access_entries = local.cluster_access_entries

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

# --- What the owner of a brought cluster must do ----------------------------------
#
# Listed in the required_cluster_owner_actions output. The deployer is the IAM
# role or user behind the apply's credentials (the role, not its session).

data "aws_caller_identity" "current" {
  count = local.create_cluster ? 0 : 1
}

data "aws_iam_session_context" "deployer" {
  count = local.create_cluster ? 0 : 1
  arn   = data.aws_caller_identity.current[0].arn
}

locals {
  deployer_arn = local.create_cluster ? "" : data.aws_iam_session_context.deployer[0].issuer_arn

  brought_cluster_endpoint_public = local.create_cluster ? true : data.aws_eks_cluster.existing[0].vpc_config[0].endpoint_public_access != false

  # Ports the load balancers send traffic to on the nodes (load-balancers.tf).
  lb_target_ports = concat([7233, 8083], local.create_edge_lb ? [8443, 8090] : [])

  cluster_owner_actions = local.create_cluster ? [] : concat(
    [
      "An EKS access entry on ${local.cluster_name} for the deployer (${local.deployer_arn}) with AmazonEKSClusterAdminPolicy: compositions/app reads the cluster, creates the namespace ${local.sa_namespace} and installs the chart. To keep the deployer to that namespace, use AmazonEKSAdminPolicy scoped to ${local.sa_namespace} plus a Role there, bound to a Kubernetes group on the access entry, for targetgroupbindings.elbv2.k8s.aws and secretproviderclasses.secrets-store.csi.x-k8s.io, which the access policy does not cover. Then create the namespace yourself and set create_namespace = false in compositions/app",
      "IAM permissions for the deployer (${local.deployer_arn}): eks:DescribeCluster${var.create_pod_identity_associations ? ", eks:CreatePodIdentityAssociation and eks:DeletePodIdentityAssociation" : ""} on ${local.cluster_name}, and ec2:AuthorizeSecurityGroupIngress and ec2:RevokeSecurityGroupIngress on ${local.node_security_group_id}: the apply lets the load balancers in on TCP ${join(", ", local.lb_target_ports)}",
      "The EKS add-ons eks-pod-identity-agent and aws-secrets-store-csi-driver-provider on ${local.cluster_name}: the workloads get AWS credentials through Pod Identity, and the secrets-sync hook reads Secrets Manager through the Secrets Store CSI driver",
      local.create_lb_controller_role
      ? "The AWS Load Balancer Controller in kube-system with the service account aws-load-balancer-controller, which the role we created is bound to: set aws_load_balancer_controller.enabled = true in compositions/app, or run your own install with that service account. The chart binds its Services to our target groups through it"
      : "The AWS Load Balancer Controller (v2.x, with the TargetGroupBinding resource) on ${local.cluster_name}, allowed to register targets in the target groups under global.infra.targetGroups in autoheal_values. Its standard IAM policy allows that. The chart binds its Services to them through it",
    ],
    local.brought_cluster_endpoint_public ? [] : [
      "A network path to the private API endpoint of ${local.cluster_name} from where compositions/app runs, and TCP 443 from there allowed on the cluster security group ${local.cluster_security_group_id}",
    ],
    local.create_registry ? [
      "The IAM policy ${local.id}-ecr-pull-through on the node role of ${local.cluster_name}: the nodes pull the chart images through the pull-through cache",
    ] : [],
    var.existing_registry_url != "" ? [
      "Pull access to ${var.existing_registry_url} for the nodes of ${local.cluster_name}: the chart images come from it",
    ] : [],
  )
}

# --- Who may use the cluster we create ------------------------------------------
#
# Access entries, one per principal. Admins get AmazonEKSClusterAdminPolicy and
# viewers AmazonEKSViewPolicy (workloads and pod logs, no Secrets), both across
# the cluster. The identity that runs the apply is admin through
# bootstrap_cluster_creator_admin_permissions.
#
# An IAM Identity Center permission set appears in each account it is assigned
# to as a role named AWSReservedSSO_<name>_<random suffix>, under the path
# /aws-reserved/sso.amazonaws.com/. The role is looked up by the permission set
# name, so the suffix never sits in a file. An access entry is bound to the
# role's unique ID, not its ARN: if the role is recreated (the assignment
# removed and added again), a new apply replaces the entry.

locals {
  sso_permission_sets = local.create_cluster ? merge(
    { for n in var.cluster_admin_sso_permission_sets : "sso-admin-${n}" => n },
    { for n in var.cluster_viewer_sso_permission_sets : "sso-viewer-${n}" => n },
  ) : {}

  eks_access_policy_arns = {
    admin  = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    viewer = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  }

  cluster_access_entries = merge(
    { for arn in var.cluster_admin_principal_arns : arn => { principal_arn = arn, policy_arn = local.eks_access_policy_arns.admin } },
    { for arn in var.cluster_viewer_principal_arns : arn => { principal_arn = arn, policy_arn = local.eks_access_policy_arns.viewer } },
    { for k, d in data.aws_iam_roles.sso : k => {
      principal_arn = one(d.arns)
      policy_arn    = startswith(k, "sso-viewer-") ? local.eks_access_policy_arns.viewer : local.eks_access_policy_arns.admin
    } },
  )
}

data "aws_iam_roles" "sso" {
  for_each = local.sso_permission_sets

  # Permission set names may hold . and +, which are regex operators.
  name_regex  = "^AWSReservedSSO_${replace(each.value, "/([.+])/", "\\$1")}_[0-9a-f]+$"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"

  lifecycle {
    postcondition {
      condition     = length(self.arns) == 1
      error_message = "Found ${length(self.arns)} IAM Identity Center roles for the permission set ${each.value} in account ${var.account_id}, not one. Assign the permission set to this account in IAM Identity Center and check the name, or list the role in cluster_admin_principal_arns or cluster_viewer_principal_arns instead."
    }
  }
}
