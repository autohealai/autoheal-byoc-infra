# The cross-cloud output contract. compositions/azure-byoc emits the SAME names, so
# the Autoheal app install is cloud-agnostic (docs/MODULE_STANDARD.md §8).

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "postgres_host" {
  description = "Aurora PostgreSQL writer endpoint."
  value       = module.rds.host
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint (host:port, in-transit encrypted, SG-gated)."
  value       = module.elasticache.endpoint
}

output "object_store" {
  description = "S3 bucket name for attachments."
  value       = module.s3.bucket_name
}

output "secret_store_uri" {
  description = "Secrets Manager prefix ARN the app reads secrets under (grant is on '<this>/*')."
  value       = module.secrets.secret_store_uri
}

output "registry" {
  description = "Account-level ECR registry endpoint."
  value       = module.ecr.registry_url
}

output "runner_identity" {
  description = "App IRSA role ARN (annotate on the app service account)."
  value       = module.irsa.role_arn
}

# -- Extras the app install / later steps need (not part of the shared contract) --

output "vpc_id" {
  description = "VPC ID (fed to the separate runner-asg apply)."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (fed to the separate runner-asg apply)."
  value       = module.vpc.private_subnet_ids
}

output "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (for any further IRSA roles)."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "EKS OIDC issuer URL (for any further IRSA roles)."
  value       = module.eks.oidc_provider_url
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA data (for kubeconfig)."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}
