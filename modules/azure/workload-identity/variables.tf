# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "resource_group_name" {
  type        = string
  description = "Resource group the identity lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "oidc_issuer_url" {
  type        = string
  description = "AKS OIDC issuer URL the federated credentials trust (modules/azure/aks output oidc_issuer_url)."
}

variable "federated_service_accounts" {
  type = list(object({
    namespace       = string
    service_account = string
  }))
  description = "Kubernetes service accounts federated to this identity (subject system:serviceaccount:<ns>:<sa>)."
}

variable "key_vault_id" {
  type        = string
  default     = ""
  description = "Key Vault to grant Key Vault Secrets User (ESO reads secrets)."
}

variable "kv_role_enabled" {
  type        = bool
  default     = true
  description = "Assign Key Vault Secrets User on var.key_vault_id. Plan-time bool: key_vault_id is a computed id, so it cannot gate count directly."
}

variable "storage_account_id" {
  type        = string
  default     = ""
  description = "Scope of the Storage Blob Data Contributor grant: a storage account ID, or a container's resource manager ID to limit the grant to one container."
}

variable "blob_role_enabled" {
  type        = bool
  default     = true
  description = "Assign Storage Blob Data Contributor on var.storage_account_id. Plan-time bool: storage_account_id is a computed id, so it cannot gate count directly."
}

variable "acr_id" {
  type        = string
  default     = ""
  description = "ACR to grant AcrPull when acr_pull_enabled is true (kubelet identity usually covers pulls; set only if the app itself pulls)."
}

variable "acr_pull_enabled" {
  type        = bool
  default     = false
  description = "Assign AcrPull on var.acr_id. Plan-time bool: acr_id is often a computed id, so it cannot gate count directly."
}
