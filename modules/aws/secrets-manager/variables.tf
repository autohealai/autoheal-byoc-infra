# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "secret_prefix" {
  type        = string
  description = "Prefix each secret name is created under, e.g. 'tenants/avid'. The IRSA policy is scoped to '<prefix>/*'."

  validation {
    condition     = length(var.secret_prefix) > 0 && !startswith(var.secret_prefix, "/") && !endswith(var.secret_prefix, "/")
    error_message = "secret_prefix must be non-empty and must not start or end with '/'."
  }
}

variable "secrets" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Map of secret key -> secret string. Each becomes a secret named '<secret_prefix>/<key>'. Values land in state; seed only what the app needs, pass via sensitive composition inputs."
}

variable "recovery_window_in_days" {
  type        = number
  default     = 7
  description = "Days AWS retains a deleted secret before permanent removal. 0 = delete immediately (no recovery)."
}
