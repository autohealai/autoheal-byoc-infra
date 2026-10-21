# S3: the attachments and artifacts buckets we create, or the customer's
# (existing_attachments_bucket_arn, existing_artifacts_bucket_arn), and the
# tenant bucket.
#
# Every bucket we create has versioning, SSE-KMS with the storage key and an S3
# bucket key, all four public access blocks, bucket-owner-enforced object
# ownership, a policy that denies requests without TLS, a rule that cleans up
# incomplete multipart uploads and optional server access logs. The attachments
# bucket also allows browser uploads from https://<hostname>.
#
# The tenant bucket (<tenant_bucket_prefix><tenant_id>) holds the Git Registry
# and tool outputs. api-server-go owns its lifecycle rules, which it merges at
# startup, so we set none on it. With create_tenant_bucket = false api-server-go
# creates the bucket itself at first use.

locals {
  bucket_lifecycle_rules = [
    {
      id                                     = "abort-incomplete-multipart"
      abort_incomplete_multipart_upload_days = 1
      noncurrent_version_expiration_days     = var.s3_noncurrent_version_expiration_days
    },
  ]
}

module "attachments_bucket" {
  source = "../../modules/aws/s3"
  count  = local.create_attachments_bucket ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["attachments"]
  tags        = var.tags

  bucket          = local.attachments_bucket_create_name
  force_destroy   = var.s3_force_destroy
  kms_key_arn     = local.kms_key_arns.storage
  lifecycle_rules = local.bucket_lifecycle_rules

  cors_rules = [
    {
      allowed_methods = ["GET", "PUT", "POST", "HEAD"]
      allowed_origins = ["https://${local.hosts.app}"]
      expose_headers  = ["ETag"]
    },
  ]

  access_log_bucket = var.s3_access_log_bucket
  access_log_prefix = "${local.attachments_bucket_create_name}/"
}

module "artifacts_bucket" {
  source = "../../modules/aws/s3"
  count  = local.create_artifacts_bucket ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["artifacts"]
  tags        = var.tags

  bucket          = local.artifacts_bucket_create_name
  force_destroy   = var.s3_force_destroy
  kms_key_arn     = local.kms_key_arns.storage
  lifecycle_rules = local.bucket_lifecycle_rules

  access_log_bucket = var.s3_access_log_bucket
  access_log_prefix = "${local.artifacts_bucket_create_name}/"
}

module "tenant_bucket" {
  source = "../../modules/aws/s3"
  count  = var.create_tenant_bucket ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["tenant"]
  tags        = var.tags

  bucket          = local.tenant_bucket
  force_destroy   = var.s3_force_destroy
  kms_key_arn     = local.kms_key_arns.storage
  lifecycle_rules = []

  access_log_bucket = var.s3_access_log_bucket
  access_log_prefix = "${local.tenant_bucket}/"
}

# Brought buckets are read to check their region.
data "aws_s3_bucket" "existing" {
  for_each = {
    for k, v in { attachments = local.existing.attachments_bucket, artifacts = local.existing.artifacts_bucket } : k => v if v != ""
  }
  bucket = each.value
}
