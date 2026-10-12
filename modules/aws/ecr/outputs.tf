output "registry_url" {
  description = "Account-level ECR registry endpoint. Maps to the cross-cloud output contract 'registry'."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

output "repository_urls" {
  description = "Map of repository name -> full repository URL."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of repository name -> ARN."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
