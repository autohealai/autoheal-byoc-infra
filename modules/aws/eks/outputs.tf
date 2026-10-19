output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded cluster CA certificate, as AWS returns it. Public, not a secret."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the control plane."
  value       = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = "ID of the security group EKS created for the cluster. The control plane and all nodes use it; allow it on data stores the pods reach."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_role_arn" {
  description = "ARN of the IAM role the control plane uses."
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "ARN of the node IAM role."
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the node IAM role, for attaching more policies outside the module."
  value       = aws_iam_role.node.name
}

output "node_group_name" {
  description = "Name of the managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster. Not used for workload credentials here (Pod Identity is), but useful for external identity federation."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "ebs_csi_driver_role_arn" {
  description = "ARN of the IAM role the EBS CSI driver uses through Pod Identity. Empty when aws-ebs-csi-driver is not in addons."
  value       = join("", aws_iam_role.ebs_csi[*].arn)
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group that receives control plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}
