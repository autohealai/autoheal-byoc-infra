output "replication_group_id" {
  description = "Replication group ID."
  value       = aws_elasticache_replication_group.this.id
}

output "arn" {
  description = "Replication group ARN."
  value       = aws_elasticache_replication_group.this.arn
}

output "primary_endpoint_address" {
  description = "Primary (read and write) endpoint hostname. Clients connect with TLS and the AUTH token."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint hostname. It spreads reads over the replicas and resolves to the primary when there are none."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Port the cache listens on."
  value       = aws_elasticache_replication_group.this.port
}

output "security_group_id" {
  description = "ID of the security group the module created. Null with security_group_ids."
  value       = one(aws_security_group.this[*].id)
}

output "security_group_ids" {
  description = "Security groups the cache uses: the one the module created, or security_group_ids."
  value       = local.security_group_ids
}
