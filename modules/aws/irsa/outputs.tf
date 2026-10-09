output "role_arn" {
  description = "IAM role ARN to annotate on the app service account (eks.amazonaws.com/role-arn). Maps to the cross-cloud output contract 'runner_identity'."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "IAM role name."
  value       = aws_iam_role.this.name
}
