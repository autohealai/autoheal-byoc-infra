output "role_arn" {
  description = "ARN of the IAM role."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IAM role, for attaching more policies outside the module."
  value       = aws_iam_role.this.name
}

output "association_arns" {
  description = "Pod Identity association ARNs keyed by \"<namespace>/<service_account>\". Empty when association_enabled is false."
  value       = { for k, a in aws_eks_pod_identity_association.this : k => a.association_arn }
}
