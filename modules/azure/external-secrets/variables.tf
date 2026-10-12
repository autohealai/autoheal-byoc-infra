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
  description = "AKS OIDC issuer URL the federated credential trusts (modules/azure/aks output oidc_issuer_url)."
}

variable "key_vault_id" {
  type        = string
  description = "Key Vault the ESO controller may read (Key Vault Secrets User). The app/install layer points the ClusterSecretStore at this vault's URI."
}

variable "eso_namespace" {
  type        = string
  default     = "external-secrets"
  description = "Namespace the ESO controller runs in (the federated SA subject)."
}

variable "eso_service_account" {
  type        = string
  default     = "external-secrets"
  description = "The ESO controller ServiceAccount federated to this identity. Must match the SA the operator install uses and the ClusterSecretStore serviceAccountRef."
}
