output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet ids (one per AZ)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet ids (one per AZ); EKS nodes, RDS, ElastiCache and the runner ASG live here."
  value       = aws_subnet.private[*].id
}

output "nat_public_ips" {
  description = "Static egress IPs of the per-AZ NAT gateways (for outbound allowlisting)."
  value       = aws_eip.nat[*].public_ip
}
