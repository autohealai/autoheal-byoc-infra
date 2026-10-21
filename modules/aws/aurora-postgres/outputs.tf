output "cluster_identifier" {
  description = "Cluster identifier."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  description = "Cluster resource ID (cluster-...), used in rds-db:connect IAM policies."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "endpoint" {
  description = "Writer endpoint hostname."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint hostname. It resolves to the writer while the cluster has no readers."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "Port the cluster listens on."
  value       = aws_rds_cluster.this.port
}

output "master_username" {
  description = "Master user name."
  value       = aws_rds_cluster.this.master_username
}

output "security_group_id" {
  description = "ID of the cluster's security group."
  value       = aws_security_group.this.id
}
