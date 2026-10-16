# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "resource_group_name" {
  type        = string
  description = "Resource group the account lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "account_name_override" {
  type        = string
  default     = ""
  description = "Force an exact storage account name (lowercase alphanumeric, <=24). Empty = derive a sanitized name from the label id."
}

variable "container_name" {
  type        = string
  default     = "attachments"
  description = "Blob container name."
}

variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Enable blob versioning on the account. The Git Registry expects it on (it is the Azure equivalent of the S3 bucket versioning the app sets on AWS)."
}

variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 90
  description = "Delete noncurrent blob versions this many days after they become noncurrent (same default as modules/aws/s3). 0 = keep them forever. Ignored when versioning_enabled = false."

  validation {
    condition     = var.noncurrent_version_expiration_days >= 0 && var.noncurrent_version_expiration_days == floor(var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be a whole number >= 0."
  }
}

variable "blob_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Blob soft-delete retention in days (1-365). 0 = soft delete off."

  validation {
    condition     = var.blob_soft_delete_retention_days == 0 || (var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365)
    error_message = "blob_soft_delete_retention_days must be 0 (off) or 1-365."
  }
}

variable "container_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Container soft-delete retention in days (1-365). 0 = soft delete off. Protects the per-tenant Git Registry containers."

  validation {
    condition     = var.container_soft_delete_retention_days == 0 || (var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365)
    error_message = "container_soft_delete_retention_days must be 0 (off) or 1-365."
  }
}

variable "pitr_enabled" {
  type        = bool
  default     = false
  description = "Enable point-in-time restore for block blobs (turns on the change feed and last-access tracking). Lets you rewind the account to an earlier moment. Recommended for production: true."
}

variable "blob_restore_days" {
  type        = number
  default     = 6
  description = "How far back point-in-time restore can rewind, in days. Must be LESS than blob_soft_delete_retention_days. Ignored when pitr_enabled = false."

  validation {
    condition     = var.blob_restore_days >= 1 && var.blob_restore_days <= 364
    error_message = "blob_restore_days must be between 1 and 364 (and strictly less than blob_soft_delete_retention_days)."
  }
}

variable "cmk_key_vault_key_id" {
  type        = string
  default     = ""
  description = "Key Vault key id for customer-managed encryption at rest. Empty = Microsoft-managed key (still encrypted). The vault must have purge protection on."
}

variable "cmk_identity_id" {
  type        = string
  default     = ""
  description = "User-assigned identity id used to reach the CMK key. Required when cmk_key_vault_key_id is set."
}

variable "account_tier" {
  type        = string
  default     = "Standard"
  description = "Storage account tier."
}

variable "account_replication_type" {
  type        = string
  default     = "LRS"
  description = "Replication: LRS, ZRS, GRS, ..."
}

variable "network_default_action" {
  type        = string
  default     = "Deny"
  description = "Storage firewall default action. Deny (recommended) = only the private endpoint, bypassed Azure services, and allowed_ip_ranges may reach the account. Use Allow only for playground accounts without a private endpoint."

  validation {
    condition     = contains(["Allow", "Deny"], var.network_default_action)
    error_message = "network_default_action must be exactly \"Allow\" or \"Deny\" (case-sensitive; the Azure storage API rejects any other value)."
  }
}

variable "allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = "Public IPs/CIDRs allowed through the storage firewall when default_action=Deny (e.g. the Terraform apply host, which creates the container over the data plane)."
}
