output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Availability zones the subnets are spread over, in the order of every subnet list output."
  value       = var.availability_zones
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes and pods), one per availability zone."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT gateways and internet-facing load balancers), one per availability zone."
  value       = aws_subnet.public[*].id
}

output "data_subnet_ids" {
  description = "Data subnet IDs (Aurora and ElastiCache), one per availability zone. Empty when data_subnet_cidrs is empty."
  value       = aws_subnet.data[*].id
}

output "private_route_table_ids" {
  description = "Private route table IDs, one per availability zone."
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "data_route_table_id" {
  description = "ID of the data route table (no internet route). Empty when data_subnet_cidrs is empty."
  value       = join("", aws_route_table.data[*].id)
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT gateways, i.e. the egress IPs to allowlist on external services. Empty when nat_gateway_mode is none."
  value       = aws_eip.nat[*].public_ip
}

output "interface_endpoint_security_group_id" {
  description = "ID of the security group shared by the interface endpoints. Empty when interface_endpoints is empty."
  value       = join("", aws_security_group.endpoints[*].id)
}

output "flow_log_group_name" {
  description = "Name of the CloudWatch log group that receives VPC flow logs. Empty when flow_logs_enabled is false."
  value       = join("", aws_cloudwatch_log_group.flow_logs[*].name)
}
