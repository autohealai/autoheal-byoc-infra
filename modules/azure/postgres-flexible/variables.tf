# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "resource_group_name" {
  type        = string
  description = "Resource group the server lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "delegated_subnet_id" {
  type        = string
  description = "VNet subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers (private, no public access). Use modules/azure/vnet output subnet_db_id."
}

variable "private_dns_zone_id" {
  type        = string
  description = "Private DNS zone id for the server FQDN. Use modules/azure/vnet output pg_private_dns_zone_id."
}

variable "administrator_login" {
  type        = string
  default     = "pgadmin"
  description = "Server admin username."
}

variable "administrator_password" {
  type        = string
  sensitive   = true
  description = "Admin password. The composition generates one and also seeds it into Key Vault for ESO; never commit a real value."
}

variable "sku_name" {
  type        = string
  default     = "GP_Standard_D2ds_v5"
  description = "azurerm combined tier+size (e.g. GP_Standard_D2ds_v5, MO_Standard_E2ds_v5). BYOC policy = provisioned (GP_/MO_), never Burstable (B_), for a real install."

  validation {
    condition     = can(regex("^(GP_|MO_|B_)", var.sku_name))
    error_message = "sku_name must start with GP_, MO_, or B_ (Burstable only for throwaway play environments)."
  }
}

variable "postgres_version" {
  type        = string
  default     = "16"
  description = "Major PostgreSQL version."
}

variable "storage_mb" {
  type        = number
  default     = 32768
  description = "Storage size in MB."
}

variable "extensions" {
  type        = list(string)
  default     = ["VECTOR", "BTREE_GIN", "PG_TRGM", "HSTORE", "UUID-OSSP"]
  description = "Extensions added to azure.extensions. Every extension must be allow-listed here BEFORE any CREATE EXTENSION runs; Azure Flexible enforces this where RDS did not. VECTOR=pgvector, BTREE_GIN=Temporal advanced-visibility."
}
