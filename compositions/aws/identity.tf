# Workload identities: one IAM role per chart workload group, bound to the
# chart's service accounts through EKS Pod Identity. No pod uses the node role
# (IMDS hop limit 1) and no long-lived AWS key exists anywhere.
#
#   secrets        autoheal-hooks, the secrets-sync hook Job and CronJob. Reads
#                  the install secrets (<secrets_prefix>*) through the Secrets
#                  Store CSI driver and decrypts them with the secrets key.
#   api_server     api-server-go. Reads and writes the buckets, keeps the tenant
#                  bucket's versioning and lifecycle rules, and manages the
#                  runtime secrets under <runtime_secrets_prefix>/. Bedrock when
#                  bedrock_access_enabled.
#   agents_worker  agents-py-http and agents-py-worker. Read and write the
#                  buckets. Bedrock when bedrock_access_enabled.
#   lb_controller  kube-system/aws-load-balancer-controller, when we create the
#                  cluster (create_load_balancer_controller_role). Registers pod
#                  IPs in our target groups only.
#
# With create_pod_identity_associations = false the roles are still created and
# the required_role_assignments output lists the associations to make.

locals {
  sa_namespace = var.service_accounts.namespace

  bedrock_resource_arns = length(var.bedrock_resource_arns) > 0 ? var.bedrock_resource_arns : [
    "arn:${local.partition}:bedrock:*::foundation-model/*",
    "arn:${local.partition}:bedrock:*:${var.account_id}:inference-profile/*",
    "arn:${local.partition}:bedrock:*:${var.account_id}:application-inference-profile/*",
  ]

  # Inline policies per role. Keys are static so the module's for_each is known
  # at plan time; the policy text may not be.
  bedrock_policy = { for k, v in { bedrock = data.aws_iam_policy_document.bedrock.json } : k => v if var.bedrock_access_enabled }
}

# --- Policy documents ---------------------------------------------------------

data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid       = "ReadInstallSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["${local.secret_arn_base}${local.secrets_prefix}*"]
  }

  statement {
    sid       = "DecryptInstallSecrets"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arns.secrets]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.region}.${local.dns_suffix}"]
    }
  }
}

# Object access to the attachments, artifacts and tenant buckets, shared by
# api-server-go and the agents services.
data "aws_iam_policy_document" "storage" {
  statement {
    sid = "ListBuckets"
    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:ListBucketMultipartUploads",
      "s3:GetBucketLocation",
    ]
    resources = values(local.bucket_arns)
  }

  statement {
    sid = "ReadWriteObjects"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = [for arn in values(local.bucket_arns) : "${arn}/*"]
  }

  statement {
    sid       = "UseStorageKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [local.kms_key_arns.storage]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.${local.dns_suffix}"]
    }
  }
}

# api-server-go checks the tenant bucket at startup: it turns versioning on and
# merges the Git Registry lifecycle rules. When we do not create the bucket it
# creates it, with SSE-S3 and the public access block.
data "aws_iam_policy_document" "tenant_bucket" {
  statement {
    sid = "KeepTenantBucket"
    actions = concat(
      [
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetLifecycleConfiguration",
        "s3:PutLifecycleConfiguration",
      ],
      var.create_tenant_bucket ? [] : [
        "s3:CreateBucket",
        "s3:PutEncryptionConfiguration",
        "s3:PutBucketPublicAccessBlock",
      ],
    )
    resources = [local.bucket_arns.tenant]
  }
}

# Runtime secrets: the integration credentials users enter. Names are
# <runtime_secrets_prefix>/tenants/<tenant>/..., default key aws/secretsmanager.
# ListSecrets has no resource-level scope.
data "aws_iam_policy_document" "runtime_secrets" {
  statement {
    sid = "ManageRuntimeSecrets"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:RestoreSecret",
      "secretsmanager:TagResource",
    ]
    resources = ["${local.secret_arn_base}${local.runtime_secrets_prefix}/*"]
  }

  statement {
    sid       = "ListSecrets"
    actions   = ["secretsmanager:ListSecrets"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "bedrock" {
  statement {
    sid       = "InvokeModels"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = local.bedrock_resource_arns
  }
}

# The controller only reconciles the chart's TargetGroupBindings: it reads load
# balancer and network state and registers pod IPs in our target groups. It
# cannot create or change load balancers or security groups.
data "aws_iam_policy_document" "lb_controller" {
  #trivy:ignore:AVD-AWS-0057 Describe calls have no resource-level scope.
  statement {
    sid = "Describe"
    actions = [
      "elasticloadbalancing:Describe*",
      "ec2:Describe*",
      "ec2:GetSecurityGroupsForVpc",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "RegisterTargets"
    actions   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
    resources = values(local.target_group_arns)
  }
}

# --- Roles --------------------------------------------------------------------

module "secrets_identity" {
  source = "../../modules/aws/pod-identity"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["secrets"]
  tags        = var.tags

  cluster_name             = local.cluster_name
  associations             = [for sa in var.service_accounts.secrets : { namespace = local.sa_namespace, service_account = sa }]
  association_enabled      = var.create_pod_identity_associations
  permissions_boundary_arn = var.iam_permissions_boundary_arn

  inline_policies = {
    secrets = data.aws_iam_policy_document.secrets_read.json
  }
}

module "api_server_identity" {
  source = "../../modules/aws/pod-identity"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["api-server"]
  tags        = var.tags

  cluster_name             = local.cluster_name
  associations             = [for sa in var.service_accounts.api_server : { namespace = local.sa_namespace, service_account = sa }]
  association_enabled      = var.create_pod_identity_associations
  permissions_boundary_arn = var.iam_permissions_boundary_arn

  inline_policies = merge(
    {
      storage         = data.aws_iam_policy_document.storage.json
      tenant-bucket   = data.aws_iam_policy_document.tenant_bucket.json
      runtime-secrets = data.aws_iam_policy_document.runtime_secrets.json
    },
    local.bedrock_policy,
  )
}

module "agents_worker_identity" {
  source = "../../modules/aws/pod-identity"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["agents-worker"]
  tags        = var.tags

  cluster_name             = local.cluster_name
  associations             = [for sa in var.service_accounts.agents_worker : { namespace = local.sa_namespace, service_account = sa }]
  association_enabled      = var.create_pod_identity_associations
  permissions_boundary_arn = var.iam_permissions_boundary_arn

  inline_policies = merge(
    { storage = data.aws_iam_policy_document.storage.json },
    local.bedrock_policy,
  )
}

module "lb_controller_identity" {
  source = "../../modules/aws/pod-identity"
  count  = local.create_lb_controller_role ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["lb-controller"]
  tags        = var.tags

  cluster_name             = local.cluster_name
  associations             = [{ namespace = "kube-system", service_account = "aws-load-balancer-controller" }]
  association_enabled      = var.create_pod_identity_associations
  permissions_boundary_arn = var.iam_permissions_boundary_arn

  inline_policies = {
    lb-controller = data.aws_iam_policy_document.lb_controller.json
  }
}

locals {
  # Associations an administrator must create when we may not.
  role_bindings = concat(
    [for sa in var.service_accounts.secrets : { ns = local.sa_namespace, sa = sa, role = module.secrets_identity.role_arn }],
    [for sa in var.service_accounts.api_server : { ns = local.sa_namespace, sa = sa, role = module.api_server_identity.role_arn }],
    [for sa in var.service_accounts.agents_worker : { ns = local.sa_namespace, sa = sa, role = module.agents_worker_identity.role_arn }],
    [for m in module.lb_controller_identity : { ns = "kube-system", sa = "aws-load-balancer-controller", role = m.role_arn }],
  )
}
