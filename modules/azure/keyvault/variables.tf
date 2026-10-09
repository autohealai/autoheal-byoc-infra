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
  description = "Object id of the principal running Terraform. Granted Key Vault Secrets Officer so the apply can seed secrets (RBAC-mode vaults enforce data-plane RBAC)."
}

variable "secrets" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Secret name -> value to seed (e.g. the generated PG password, Redis URL). ESO syncs these into the cluster."
}

variable "purge_protection_enabled" {
  type        = bool
  default     = false
  description = "Enable purge protection (irreversible; leave false for play/throwaway vaults)."
}
