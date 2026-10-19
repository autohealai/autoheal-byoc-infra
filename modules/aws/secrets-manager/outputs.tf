output "secret_arns" {
  description = "Secret ARN per entry. AWS adds a random six-character suffix, so use arn_pattern for IAM policies."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}

output "secret_names" {
  description = "Full secret name (<name_prefix><entry>) per entry."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.name }
}

output "name_prefix" {
  description = "Prefix all secret names start with."
  value       = var.name_prefix
}

output "arn_pattern" {
  description = "ARN pattern that matches every secret under name_prefix in this region, for GetSecretValue in an IAM policy."
  value       = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name_prefix}*"
}
