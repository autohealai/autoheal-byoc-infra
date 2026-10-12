# ECR repositories for a BYOC-on-EKS Autoheal install. ECR is an account-level
# registry (`<account>.dkr.ecr.<region>.amazonaws.com`); this module creates the
# per-service repositories under it and a lifecycle policy that prunes old images.
# Nodes pull via the node-group role (AmazonEC2ContainerRegistryReadOnly, wired in
# modules/aws/eks); the runner pulls via its instance profile (modules/aws/runner-asg).
#
# Azure analogue: modules/azure/acr (one registry resource). Here the "registry" is
# the account endpoint, exposed as the registry_url output. Naming/tags: module.this.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Tag mutability is operator-controlled (var.image_tag_mutability). The BYOC image
# flow mirrors upstream images under moving tags (e.g. :latest, :dev), which requires
# MUTABLE; set IMMUTABLE per-repo for release repositories that only take digests.
#trivy:ignore:AVD-AWS-0031 Mutable tags are required to mirror moving tags (:latest/:dev); operator-gated via image_tag_mutability.
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = merge(module.this.tags, { Name = each.value })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = var.tag_prefix_list
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images older than ${var.untagged_image_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_days
        }
        action = { type = "expire" }
      }
    ]
  })
}
