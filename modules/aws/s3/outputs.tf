output "bucket_id" {
  description = "Bucket name. Known at plan time, so it can feed another bucket's access_log_bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name (<bucket>.s3.<region>.amazonaws.com), for clients and presigned URLs that must hit the bucket's region."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
