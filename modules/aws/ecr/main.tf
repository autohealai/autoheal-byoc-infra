# Private mirror of the public Autoheal registry through an ECR pull-through
# cache. The Azure analogue is modules/azure/acr.
#
# Nothing is pushed. The first pull of <registry_host>/<repository_prefix>/<path>
# makes ECR create the repository <repository_prefix>/<path>, copy the image from
# <upstream_registry_url>/<path>, and check upstream again at most once every 24
# hours. The repository creation template gives every repository the rule
# creates the same settings: encryption (the KMS key when set), tag mutability,
# a lifecycle policy that expires untagged images, and the module tags.
#
# ECR creates those repositories with the template's role. The role is needed
# because the template sets tags (and the KMS key when set), and it may only
# create and tag repositories under the prefix.
#
# The first pull of each image needs a route from ECR to the upstream registry;
# ECR VPC endpoints alone do not provide one. Pullers need pull_policy_json,
# which includes ecr:BatchImportUpstreamImage and ecr:CreateRepository.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  registry_host          = "${local.account_id}.dkr.ecr.${local.region}.${data.aws_partition.current.dns_suffix}"
  image_registry         = trimsuffix("${local.registry_host}/${var.repository_prefix}/${var.upstream_namespace}", "/")
  repository_arn_pattern = "arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/${var.repository_prefix}/*"

  kms_enabled = var.kms_key_arn != ""

  # IAM role names are limited to 64 characters. A long label id is cut and
  # given a short hash so two long ids still get different names.
  role_name_full = "${module.this.id}-ecr-template"
  role_name      = length(local.role_name_full) <= 64 ? local.role_name_full : "${substr(local.role_name_full, 0, 57)}-${substr(md5(local.role_name_full), 0, 6)}"

  lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images ${var.untagged_expiry_days} days after they were pulled in"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = var.untagged_expiry_days
      }
      action = { type = "expire" }
    }]
  })

  # The KMS statement is filtered in or out with for/if so kms_key_arn may be a
  # key created in the same apply.
  creation_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid      = "CreateRepositoriesUnderPrefix"
        Effect   = "Allow"
        Action   = ["ecr:CreateRepository", "ecr:TagResource"]
        Resource = local.repository_arn_pattern
      }],
      [for s in [{
        Sid      = "UseRepositoryKey"
        Effect   = "Allow"
        Action   = ["kms:CreateGrant", "kms:RetireGrant", "kms:DescribeKey"]
        Resource = var.kms_key_arn
      }] : s if local.kms_enabled],
    )
  })

  pull_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PullThroughCache"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:BatchImportUpstreamImage",
          "ecr:CreateRepository",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = local.repository_arn_pattern
      },
    ]
  })
}

resource "aws_iam_role" "creation" {
  name        = local.role_name
  description = "ECR repository creation template for the ${var.repository_prefix} pull through cache."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecr.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = module.this.tags
}

resource "aws_iam_role_policy" "creation" {
  name   = "create-repositories"
  role   = aws_iam_role.creation.id
  policy = local.creation_role_policy
}

resource "aws_ecr_repository_creation_template" "this" {
  prefix          = var.repository_prefix
  description     = "Settings for repositories the ${var.repository_prefix} pull through cache rule creates."
  applied_for     = ["PULL_THROUGH_CACHE"]
  custom_role_arn = aws_iam_role.creation.arn

  image_tag_mutability = var.image_tag_mutability
  lifecycle_policy     = local.lifecycle_policy
  resource_tags        = module.this.tags

  encryption_configuration {
    encryption_type = local.kms_enabled ? "KMS" : "AES256"
    kms_key         = local.kms_enabled ? var.kms_key_arn : null
  }

  # ECR uses the role when the first pull creates a repository, so its policy
  # must be in place first.
  depends_on = [aws_iam_role_policy.creation]
}

resource "aws_ecr_pull_through_cache_rule" "this" {
  ecr_repository_prefix = var.repository_prefix
  upstream_registry_url = var.upstream_registry_url

  # A repository created before the template exists would not get its
  # settings, so the rule only goes live after the template.
  depends_on = [aws_ecr_repository_creation_template.this]
}
