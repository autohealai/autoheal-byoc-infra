# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "resource_group_name" {
  type        = string
  description = "Resource group the vault lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "name_override" {
  type        = string
  default     = ""
  description = "Force an exact vault name (<=24 chars). Empty = derive from the label id (truncated to 24)."
}

variable "tenant_id" {
  type        = string
  description = "Entra tenant id the vault belongs to."
}

variable "deployer_object_id" {
  type        = string
  description = "Object id of the principal running Terraform. Granted Key Vault Secrets Officer when deployer_role_enabled is true, so the apply can write secrets (RBAC-mode vaults enforce data-plane RBAC)."
}

variable "deployer_role_enabled" {
  type        = bool
  default     = true
  description = "Grant deployer_object_id Key Vault Secrets Officer on the vault. Set false when the deployer cannot create role assignments; an admin must then grant the role before secrets can be written."
}

variable "purge_protection_enabled" {
  type        = bool
  default     = false
  description = "Enable purge protection (irreversible; leave false for play/throwaway vaults). Required when the vault holds a customer-managed encryption key."
}

variable "soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "How many days a deleted vault or secret can be recovered (7-90). CREATE-TIME ONLY; cannot change on an existing vault. Recommended for production: 90."

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "network_default_action" {
  type        = string
  default     = "Deny"
  description = "Key Vault firewall default action. Deny (recommended) = only the private endpoint, bypassed Azure services, and allowed_ip_ranges may reach the vault. Use Allow only for playground vaults without a private endpoint."

  validation {
    condition     = contains(["Allow", "Deny"], var.network_default_action)
    error_message = "network_default_action must be exactly \"Allow\" or \"Deny\" (case-sensitive; the Azure Key Vault API rejects any other value)."
  }
}

variable "allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = "Public IPs/CIDRs allowed through the vault firewall when default_action=Deny (e.g. the Terraform apply host, which writes secrets over the data plane)."
}
