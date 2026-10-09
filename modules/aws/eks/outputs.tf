output "cluster_name" {
  description = "EKS cluster name. Maps to the cross-cloud output contract 'cluster_name'."
  value       = aws_eks_cluster.this.name
}

output "cluster_id" {
  description = "EKS cluster ID."
  value       = aws_eks_cluster.this.id
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA data (for kubeconfig)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS control plane (the one this module creates)."
  value       = aws_security_group.cluster.id
}

output "cluster_primary_security_group_id" {
  description = "EKS-managed primary security group attached to pods/nodes via the VPC CNI. Use this as the source in data-tier (RDS/ElastiCache) ingress rules."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_role_arn" {
  description = "IAM role ARN assumed by node-group instances."
  value       = aws_iam_role.node_group.arn
}

output "oidc_provider_arn" {
  description = "ARN of the cluster OIDC provider (feed to modules/aws/irsa)."
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "URL of the cluster OIDC issuer (feed to modules/aws/irsa)."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN used by the EBS CSI driver."
  value       = aws_iam_role.ebs_csi.arn
}
