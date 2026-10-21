# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "description" {
  type        = string
  description = "What the key protects, shown in the KMS console, e.g. 'Autoheal acme-prod data at rest'."

  validation {
    condition     = length(var.description) > 0 && length(var.description) <= 8192
    error_message = "description must be 1-8192 characters."
  }
}

variable "alias" {
  type        = string
  default     = ""
  description = "Key alias including the 'alias/' prefix. Empty uses 'alias/<label id>'."

  validation {
    condition     = var.alias == "" || (can(regex("^alias/[a-zA-Z0-9/_-]+$", var.alias)) && !startswith(var.alias, "alias/aws/") && length(var.alias) <= 256)
    error_message = "alias must be empty or 'alias/<name>' using letters, digits, '/', '_' and '-' (at most 256 characters), and must not start with 'alias/aws/' (reserved for AWS managed keys)."
  }
}

variable "deletion_window_in_days" {
  type        = number
  default     = 30
  description = "Days KMS waits before deleting the key after it is scheduled for deletion (7-30). The key can be recovered during this window."

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "enable_key_rotation" {
  type        = bool
  default     = true
  description = "Rotate the key material automatically every rotation_period_in_days. Old material is kept, so existing data stays readable."
}

variable "rotation_period_in_days" {
  type        = number
  default     = 365
  description = "Days between automatic rotations (90-2560). Used only when enable_key_rotation is true."

  validation {
    condition     = var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560
    error_message = "rotation_period_in_days must be between 90 and 2560."
  }
}

variable "key_administrator_arns" {
  type        = list(string)
  default     = []
  description = "IAM principal ARNs that may manage the key (policy, rotation, deletion) but not use it to encrypt or decrypt. Empty adds no statement; the account root statement still lets IAM policies grant access."
}

variable "key_user_arns" {
  type        = list(string)
  default     = []
  description = "IAM principal ARNs that may use the key to encrypt and decrypt, and create grants for AWS services. Every principal must already exist when the policy is applied, or KMS rejects it. Empty adds no statement."
}

variable "cloudwatch_logs_enabled" {
  type        = bool
  default     = false
  description = "Let the CloudWatch Logs service use the key for log groups in this account and region (needed when a log group sets kms_key_id to this key)."
}

variable "additional_policy_statements" {
  type        = any
  default     = []
  description = "Extra IAM policy statement objects appended to the key policy, written as in IAM JSON (Sid, Effect, Principal, Action, Resource, Condition), e.g. [{ Sid = \"AllowAcmeRole\", Effect = \"Allow\", Principal = { AWS = \"arn:aws:iam::111122223333:role/acme\" }, Action = [\"kms:Decrypt\"], Resource = \"*\" }]."

  validation {
    condition     = can(length(var.additional_policy_statements)) && alltrue([for s in var.additional_policy_statements : can(s.Effect)])
    error_message = "additional_policy_statements must be a list of statement objects, each with at least an Effect attribute."
  }
}
