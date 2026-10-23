# Label inputs (namespace, environment, name, attributes, tags, ...) are declared
# in label.tf and feed modules/_shared/label. Only module-specific inputs live here.

variable "resource_group_name" {
  type        = string
  description = "Resource group the network lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region for the VNet."
}

variable "address_space" {
  type        = list(string)
  default     = ["10.60.0.0/16"]
  description = "VNet address space."
}

variable "subnet_aks_prefix" {
  type        = string
  default     = "10.60.0.0/20"
  description = "Subnet for AKS nodes/pods (overlay CNI, so this only sizes nodes). Empty creates no AKS subnet, for a VNet that holds only Postgres and the private endpoints of a cluster in another VNet."
}

variable "subnet_db_prefix" {
  type        = string
  default     = "10.60.16.0/24"
  description = "Subnet delegated to PostgreSQL Flexible Server. Empty creates none, for a Postgres server with public access."
}

variable "subnet_pe_prefix" {
  type        = string
  default     = "10.60.17.0/24"
  description = "Subnet for private endpoints (KV/Blob/Foundry when private). Empty creates none, when every service uses its public endpoint."
}

variable "pg_private_dns_zone_name" {
  type        = string
  default     = ""
  description = "Private DNS zone name for PG Flexible Server. Empty disables the zone (connect installs that bring their own). Must end in .private.postgres.database.azure.com."

  validation {
    condition     = var.pg_private_dns_zone_name == "" || endswith(var.pg_private_dns_zone_name, ".private.postgres.database.azure.com")
    error_message = "pg_private_dns_zone_name must be empty or end in .private.postgres.database.azure.com."
  }
}

variable "private_endpoints_enabled" {
  type        = bool
  default     = false
  description = "Create privatelink DNS zones + VNet links for Blob and Key Vault private endpoints."
}

variable "redis_private_endpoint_enabled" {
  type        = bool
  default     = false
  description = "Create the privatelink DNS zone + VNet link for an Azure Managed Redis private endpoint (privatelink.redis.azure.net)."
}

variable "foundry_private_endpoint_enabled" {
  type        = bool
  default     = false
  description = "Create privatelink DNS zones + VNet links for an AI Foundry / Azure OpenAI private endpoint (openai + cognitiveservices + services.ai suffixes)."
}
