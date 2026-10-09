output "secret_arns" {
  description = "Map of secret key -> full secret ARN."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}

output "secret_prefix" {
  description = "The prefix all secrets were created under."
  value       = var.secret_prefix
}

output "secret_store_uri" {
  description = "Prefix ARN for the secret store. Maps to the cross-cloud output contract 'secret_store_uri'. Grant IRSA GetSecretValue on '<this>/*'."
  value       = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.secret_prefix}"
}
