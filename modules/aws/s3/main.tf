# One S3 bucket for Autoheal data (attachments, artifacts, the Git Registry). The
# Azure analogue is modules/azure/blob. Pods reach it through an EKS Pod Identity
# role (modules/aws/pod-identity), so no access keys are stored.
#
# Always on: bucket owner enforced (ACLs off), all four public access blocks, and
# a bucket policy that denies any request not made over TLS. Default encryption
# is SSE-KMS with an S3 Bucket Key when kms_key_arn is set, SSE-S3 otherwise.
#
# Inputs that may only be known after apply (kms_key_arn, additional_policy_json)
# only set attribute values; they never decide whether a resource or block
# exists, so the module plans in the same apply that creates the key or the
# policy's principals.
#
# Tags come from the null-label base (module.this); see label.tf. The bucket name
# is passed in full because bucket names are global.

data "aws_partition" "current" {}

locals {
  # Built from the name rather than read from the bucket, so the policy can be
  # planned before the bucket exists.
  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.bucket}"
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket
  force_destroy = var.force_destroy

  tags = merge(module.this.tags, { Name = var.bucket })
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    # "Disabled" is only valid for a bucket that was never versioned, so off maps
    # to "Suspended", which works in both cases.
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# SSE-S3 is the default only when the caller passes no key; set kms_key_arn for a
# customer managed key.
#trivy:ignore:AVD-AWS-0132 SSE-S3 is used only when no kms_key_arn is passed; the composition passes one.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }

    # The Bucket Key cuts KMS requests (and cost) for SSE-KMS; it has no effect on SSE-S3.
    bucket_key_enabled = var.kms_key_arn != ""
  }
}

data "aws_iam_policy_document" "this" {
  # Merged first; statements below are added after it.
  source_policy_documents = compact([var.additional_policy_json])

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json

  # A policy write can race the public access block on a new bucket.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      # An empty filter applies the rule to the whole bucket.
      filter {
        prefix = rule.value.prefix != "" ? rule.value.prefix : null
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days > 0 ? [rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days > 0 ? [rule.value.noncurrent_version_expiration_days] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days > 0 ? [rule.value.abort_incomplete_multipart_upload_days] : []
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value
        }
      }
    }
  }

  # Noncurrent version rules need versioning to be configured first.
  depends_on = [aws_s3_bucket_versioning.this]
}

# access_log_bucket is a bucket name passed by the caller, so it is known at plan
# time; it decides whether this resource exists.
resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_bucket != "" ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket
  target_prefix = var.access_log_prefix
}
