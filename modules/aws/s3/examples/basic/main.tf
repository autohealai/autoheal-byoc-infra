# Attachments bucket: KMS encrypted, versioned, CORS for browser uploads with
# presigned URLs, and lifecycle rules that clean up incomplete uploads and old
# versions. Doubles as the CI validate fixture. The KMS key ARN is a placeholder;
# the composition passes the kms module output instead.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "attachments" {
  source = "../../"

  # null-label supplies the tags; the bucket name is global, so it is passed in full.
  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["attachments"]

  bucket      = "acme-play-autoheal-attachments-111122223333"
  kms_key_arn = "arn:aws:kms:us-west-2:111122223333:key/00000000-0000-0000-0000-000000000000"

  cors_rules = [
    {
      allowed_methods = ["PUT", "GET", "HEAD"]
      allowed_origins = ["https://autoheal.acme.example.com"]
      expose_headers  = ["ETag"]
    },
  ]

  lifecycle_rules = [
    {
      id                                     = "abort-incomplete-multipart"
      abort_incomplete_multipart_upload_days = 1
    },
    {
      id                                 = "expire-noncurrent-versions"
      noncurrent_version_expiration_days = 90
    },
  ]
}

output "bucket_id" {
  description = "Bucket name."
  value       = module.attachments.bucket_id
}

output "bucket_arn" {
  description = "Bucket ARN."
  value       = module.attachments.bucket_arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name."
  value       = module.attachments.bucket_regional_domain_name
}
