output "bucket_name" {
  description = "Bucket name. Maps to the cross-cloud output contract 'object_store'."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Bucket ARN (grant the app IRSA role s3 access on this)."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
