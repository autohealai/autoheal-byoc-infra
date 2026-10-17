# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "resource_group_name" {
  type        = string
  description = "Resource group the identity lands in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "oidc_issuer_url" {
  type        = string
  description = "OIDC issuer URL of the AKS cluster the federated credentials trust (modules/azure/aks output oidc_issuer_url, or the issuer of a brought cluster)."
}

variable "key_vault_id" {
  type        = string
  description = "Key Vault the identity may read (Key Vault Secrets User)."
}

variable "service_accounts" {
  type = list(object({
    namespace       = string
    service_account = string
  }))
  default = [
    { namespace = "autoheal", service_account = "api-server-go" },
  ]
  description = "Kubernetes ServiceAccounts federated to this identity: every ServiceAccount whose pods mount the Key Vault SecretProviderClass. An identity holds at most 20 federated credentials."

  validation {
    condition     = length(var.service_accounts) <= 20
    error_message = "A user-assigned identity supports at most 20 federated credentials."
  }
}

variable "role_assignment_enabled" {
  type        = bool
  default     = true
  description = "Grant the identity Key Vault Secrets User on key_vault_id. Set false when the deployer cannot grant roles; an administrator then makes the grant."
}
