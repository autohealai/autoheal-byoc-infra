output "host" {
  description = "Writer endpoint (private). Maps to the cross-cloud output contract 'postgres_host'."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_host" {
  description = "Reader endpoint."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_rds_cluster.this.port
}

output "administrator_login" {
  description = "Master username."
  value       = var.master_username
}

output "database_name" {
  description = "Initial database name."
  value       = aws_rds_cluster.this.database_name
}

output "cluster_id" {
  description = "Cluster identifier."
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_rds_cluster.this.arn
}

output "security_group_id" {
  description = "Security group id of the cluster (reference it from clients)."
  value       = aws_security_group.cluster.id
}
