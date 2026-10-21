output "registry_host" {
  description = "Private registry host for this account and region, <account>.dkr.ecr.<region>.amazonaws.com."
  value       = local.registry_host
}

output "image_registry" {
  description = "Registry path the chart pulls app/<name> and external/<name> under (global.imageRegistry): <registry_host>/<repository_prefix>/<upstream_namespace>."
  value       = local.image_registry
}

output "repository_prefix" {
  description = "Repository prefix of the pull through cache rule."
  value       = aws_ecr_pull_through_cache_rule.this.ecr_repository_prefix
}

output "repository_arn_pattern" {
  description = "ARN pattern that matches every repository the rule creates, for IAM policies."
  value       = local.repository_arn_pattern
}

output "pull_policy_json" {
  description = "IAM policy JSON that lets a role pull through the cache: ecr:GetAuthorizationToken on *, and the pull, import and create actions on the prefix's repositories."
  value       = local.pull_policy_json
}

output "creation_role_arn" {
  description = "ARN of the IAM role ECR uses to create the cached repositories."
  value       = aws_iam_role.creation.arn
}
