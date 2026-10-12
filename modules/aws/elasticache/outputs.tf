output "endpoint" {
  description = "primary_endpoint:port. Maps to the cross-cloud output contract 'redis_endpoint'."
  value       = "${aws_elasticache_replication_group.this.primary_endpoint_address}:${aws_elasticache_replication_group.this.port}"
}

output "primary_endpoint_address" {
  description = "Primary (writer) endpoint address."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint address (empty for a single-node cache)."
  value       = try(aws_elasticache_replication_group.this.reader_endpoint_address, "")
}

output "port" {
  description = "Redis port."
  value       = aws_elasticache_replication_group.this.port
}

output "security_group_id" {
  description = "Security group id of the cache."
  value       = aws_security_group.redis.id
}

output "arn" {
  description = "ARN of the replication group."
  value       = aws_elasticache_replication_group.this.arn
}
