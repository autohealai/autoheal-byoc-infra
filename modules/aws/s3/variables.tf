# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "bucket_name_override" {
  type        = string
  default     = ""
  description = "Force an exact bucket name. Empty = derive from the label id (lowercased). Bucket names are globally unique; set this if the derived name is taken."
}

variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 90
  description = "Expire noncurrent object versions after this many days."
}

variable "enable_cors" {
  type        = bool
  default     = false
  description = "Add a CORS rule (GET/PUT) for browser uploads."
}

variable "cors_allowed_origins" {
  type        = list(string)
  default     = []
  description = "Allowed origins when enable_cors is true."

  validation {
    condition     = !var.enable_cors || length(var.cors_allowed_origins) > 0
    error_message = "cors_allowed_origins must not be empty when enable_cors is true."
  }
}
