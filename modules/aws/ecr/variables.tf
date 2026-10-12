# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "repository_names" {
  type        = list(string)
  default     = []
  description = "ECR repository names to create (relative to the account registry), e.g. ['release/api-server-go', 'release/runner-go']."
}

variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "IMMUTABLE forbids overwriting a tag; MUTABLE allows floating tags like 'latest'."

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Run the basic image vulnerability scan on push."
}

variable "encryption_type" {
  type        = string
  default     = "AES256"
  description = "AES256 (S3-managed) or KMS. kms_key_arn is used only when KMS."

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN when encryption_type is KMS. Empty uses the AWS-managed ECR key."
}

variable "max_image_count" {
  type        = number
  default     = 100
  description = "Keep at most this many tagged images per repository; older ones expire."
}

variable "tag_prefix_list" {
  type        = list(string)
  default     = ["v", "release", "main"]
  description = "Only tags starting with one of these count toward max_image_count."
}

variable "untagged_image_days" {
  type        = number
  default     = 14
  description = "Expire untagged images older than this many days."
}
