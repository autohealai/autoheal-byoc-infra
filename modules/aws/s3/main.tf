# S3 bucket for attachments / knowledge base. The Azure analogue is
# modules/azure/blob. The app reaches it via an IRSA role (modules/aws/irsa grants
# s3:* on this bucket), so no static keys are stored. Versioned, encrypted
# (SSE-S3), all public access blocked, old versions expired after 90 days.
#
# Bucket names are global and must be lowercase/DNS-safe, so we sanitize
# module.this.id; bucket_name_override forces an exact name (and is often needed to
# win a globally-unique name).

locals {
  bucket_name = var.bucket_name_override != "" ? var.bucket_name_override : lower(module.this.id)
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name
  tags   = merge(module.this.tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# The bucket is encrypted at rest with SSE-S3 (AES256). This finding asks for a
# customer-managed KMS key, which is left to the deployment to supply when CMK
# control is required (keeps the base module free of a mandatory KMS key + its cost).
#trivy:ignore:AVD-AWS-0132 SSE-S3 (AES256) is enabled; a customer-managed KMS key is operator-optional.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count  = var.enable_cors ? 1 : 0
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = ["GET", "PUT"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}
