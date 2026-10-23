output "arn" {
  description = "ARN of the NLB."
  value       = aws_lb.this.arn
}

output "arn_suffix" {
  description = "ARN suffix of the NLB, the LoadBalancer dimension of its CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "name" {
  description = "Name of the NLB."
  value       = aws_lb.this.name
}

output "dns_name" {
  description = "DNS name of the NLB, e.g. for a Route 53 alias or a CNAME record."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Route 53 hosted zone ID of the NLB, for alias records."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ID of the NLB security group."
  value       = aws_security_group.this.id
}

output "target_group_arns" {
  description = "Target group ARNs keyed like var.listeners, for the chart's TargetGroupBinding resources."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}

output "listener_arns" {
  description = "Listener ARNs keyed like var.listeners."
  value       = { for k, l in aws_lb_listener.this : k => l.arn }
}
