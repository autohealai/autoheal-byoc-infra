# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The bucket name is passed in full (bucket names are global); the label supplies
# the tags.

variable "bucket" {
  type        = string
  description = "Full bucket name. Bucket names are global across all AWS accounts, so include something unique such as the account ID."

  validation {
    condition = (
      length(var.bucket) >= 3 && length(var.bucket) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket)) &&
      !strcontains(var.bucket, "..") &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.bucket)) &&
      !startswith(var.bucket, "xn--") &&
      !startswith(var.bucket, "sthree-") &&
      !startswith(var.bucket, "amzn-s3-demo-") &&
      !endswith(var.bucket, "-s3alias") &&
      !endswith(var.bucket, "--ol-s3") &&
      !endswith(var.bucket, ".mrap") &&
      !endswith(var.bucket, "--x-s3") &&
      !endswith(var.bucket, "--table-s3")
    )
    error_message = "bucket must be 3-63 characters of lowercase letters, digits, dots and hyphens, start and end with a letter or digit, have no \"..\", not look like an IP address, not start with xn--, sthree- or amzn-s3-demo-, and not end with -s3alias, --ol-s3, .mrap, --x-s3 or --table-s3."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Let a destroy delete the bucket even when it holds objects. Keep false for a real install."
}

variable "kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN for default encryption (SSE-KMS with an S3 Bucket Key). Empty uses SSE-S3 (AES256)."

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Keep previous versions of overwritten and deleted objects. Turning it off later suspends versioning; existing versions stay."
}

variable "cors_rules" {
  type = list(object({
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string), ["*"])
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3000)
  }))
  default     = []
  description = "CORS rules, for example to let a browser upload with presigned URLs (PUT, GET, HEAD from the app origin, exposing ETag). Empty means no CORS configuration."

  validation {
    condition = alltrue([
      for r in var.cors_rules :
      length(r.allowed_methods) > 0 && length(r.allowed_origins) > 0 &&
      alltrue([for m in r.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], m)])
    ])
    error_message = "Each CORS rule needs at least one origin and one method; methods must be GET, PUT, POST, DELETE or HEAD."
  }

  validation {
    condition     = length(var.cors_rules) <= 100
    error_message = "S3 allows at most 100 CORS rules."
  }
}

variable "lifecycle_rules" {
  type = list(object({
    id                                     = string
    enabled                                = optional(bool, true)
    prefix                                 = optional(string, "")
    expiration_days                        = optional(number, 0)
    noncurrent_version_expiration_days     = optional(number, 0)
    abort_incomplete_multipart_upload_days = optional(number, 0)
  }))
  default = [
    {
      id                                     = "abort-incomplete-multipart"
      abort_incomplete_multipart_upload_days = 1
    },
  ]
  description = "Lifecycle rules. Each rule applies to objects under prefix (empty means the whole bucket); a day count of 0 leaves that action off. The default removes incomplete multipart uploads after 1 day. Empty means no lifecycle configuration."

  validation {
    condition = alltrue([
      for r in var.lifecycle_rules :
      length(r.id) >= 1 && length(r.id) <= 255 &&
      r.expiration_days >= 0 && r.noncurrent_version_expiration_days >= 0 && r.abort_incomplete_multipart_upload_days >= 0 &&
      (r.expiration_days + r.noncurrent_version_expiration_days + r.abort_incomplete_multipart_upload_days) > 0
    ])
    error_message = "Each lifecycle rule needs an id of 1-255 characters, day counts >= 0, and at least one day count above 0."
  }

  validation {
    condition     = length(distinct([for r in var.lifecycle_rules : r.id])) == length(var.lifecycle_rules)
    error_message = "Lifecycle rule ids must be unique."
  }
}

variable "access_log_bucket" {
  type        = string
  default     = ""
  description = "Bucket that receives server access logs. Empty turns access logging off. Pass a name known at plan time (a variable or this module's bucket_id output), since it decides whether the logging configuration exists."
}

variable "access_log_prefix" {
  type        = string
  default     = ""
  description = "Key prefix for the access logs in access_log_bucket, for example \"s3/<bucket>/\"."
}

variable "additional_policy_json" {
  type        = string
  default     = ""
  description = "IAM policy JSON merged into the bucket policy, ahead of the DenyInsecureTransport statement. A statement with the Sid DenyInsecureTransport is replaced by the module one."

  validation {
    condition     = var.additional_policy_json == "" || can(jsondecode(var.additional_policy_json))
    error_message = "additional_policy_json must be empty or a JSON policy document."
  }
}
