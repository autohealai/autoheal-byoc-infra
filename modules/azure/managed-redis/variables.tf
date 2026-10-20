# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "resource_group_name" {
  type        = string
  description = "Resource group the cache lands in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "sku_name" {
  type        = string
  default     = "Balanced_B0"
  description = "Managed Redis SKU, e.g. Balanced_B0, Balanced_B1, MemoryOptimized_M10. Balanced_B0 is the smallest and the one test subscriptions allow."
}

variable "high_availability_enabled" {
  type        = bool
  default     = false
  description = "Run a replica for automatic failover. Off by default to fit test subscriptions; turn on for production."
}

variable "access_keys_authentication_enabled" {
  type        = bool
  default     = true
  description = "Allow access-key authentication. The services read the key from the vault entry the composition writes, so keep this on unless they authenticate with Entra."
}

variable "client_protocol" {
  type        = string
  default     = "Encrypted"
  description = "Encrypted (TLS) or Plaintext."

  validation {
    condition     = contains(["Encrypted", "Plaintext"], var.client_protocol)
    error_message = "client_protocol must be Encrypted or Plaintext."
  }
}

variable "clustering_policy" {
  type        = string
  default     = "EnterpriseCluster"
  description = "EnterpriseCluster (single endpoint, works with non-cluster clients), OSSCluster or NoCluster."

  validation {
    condition     = contains(["EnterpriseCluster", "OSSCluster", "NoCluster"], var.clustering_policy)
    error_message = "clustering_policy must be EnterpriseCluster, OSSCluster or NoCluster."
  }
}

variable "eviction_policy" {
  type        = string
  default     = "VolatileLRU"
  description = "Eviction policy for the default database."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = false
  description = "Open the public endpoint. Azure Managed Redis has no IP firewall, so any address can then reach it; the access key and TLS still apply. Off: reach it through a private endpoint."
}
