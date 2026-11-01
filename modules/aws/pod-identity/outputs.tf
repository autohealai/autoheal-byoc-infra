output "role_arn" {
  description = "ARN of the IAM role: the one we created, or existing_role_arn when brought."
  value       = local.role_arn
}

output "role_name" {
  description = "Name of the IAM role, without its path, for attaching more policies outside the module."
  value       = local.role_name
}

output "association_arns" {
  description = "Pod Identity association ARNs keyed by \"<namespace>/<service_account>\". Empty when association_enabled is false."
  value       = { for k, a in aws_eks_pod_identity_association.this : k => a.association_arn }
}
