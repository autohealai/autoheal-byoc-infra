output "fqdns" {
  description = "Fully qualified names of the records (no trailing dot), keyed like var.records."
  value       = { for k, r in aws_route53_record.this : k => r.fqdn }
}
