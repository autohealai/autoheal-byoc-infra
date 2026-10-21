output "key_arn" {
  description = "ARN of the KMS key. Pass this to resources that take a kms_key_id or kms_key_arn."
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "ID (UUID) of the KMS key."
  value       = aws_kms_key.this.key_id
}

output "alias_name" {
  description = "Alias name, including the 'alias/' prefix."
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "ARN of the alias."
  value       = aws_kms_alias.this.arn
}
