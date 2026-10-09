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
