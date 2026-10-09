# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "resource_group_name" {
  type        = string
  description = "Resource group the registry lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "name_override" {
  type        = string
  default     = ""
  description = "Force an exact registry name (5-50 lowercase alphanumeric). Empty = derive a sanitized name from the label id."
}

variable "sku" {
  type        = string
  default     = "Standard"
  description = "Registry SKU: Basic | Standard | Premium. Private endpoints and geo-replication require Premium."

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard, or Premium."
  }
}

variable "georeplication_locations" {
  type        = list(string)
  default     = []
  description = "Extra regions to geo-replicate to (Premium only; ignored for Basic/Standard)."
}
