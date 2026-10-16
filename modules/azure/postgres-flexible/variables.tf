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

# ---------------------------------------------------------------------------
# Backup, high availability and encryption.
# Defaults preserve the current behaviour (Azure's 7-day local backup, no HA,
# Microsoft-managed key). Set the production values in the install profile.
# ---------------------------------------------------------------------------

variable "backup_retention_days" {
  type        = number
  default     = 7
  description = "How many days of automatic backups to keep (1-35). Any point in this window can be restored. Recommended for production: 35."

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "geo_redundant_backup_enabled" {
  type        = bool
  default     = false
  description = "Copy backups to the Azure paired region so they survive a whole-region outage. CREATE-TIME ONLY (cannot change on an existing server). Recommended for production: true. Cannot be combined with a customer-managed key (cmk_key_vault_key_id) yet: that needs a paired-region geo-backup key which is not wired, so enable one or the other."
}

variable "auto_grow_enabled" {
  type        = bool
  default     = false
  description = "Let the server expand its storage automatically before it fills up. Applied in place, no downtime. Default off to preserve existing behaviour; strongly recommended on for a real install (a full disk takes the database read-only)."
}

variable "high_availability_enabled" {
  type        = bool
  default     = false
  description = "Run a hot standby in a second availability zone with automatic failover. Requires a zonal region and a GP_/MO_ SKU (not Burstable). Recommended for production: true."
}

variable "delete_protection_enabled" {
  type        = bool
  default     = false
  description = "Place a resource lock that blocks deletion of the database (the Azure equivalent of AWS deletion protection; deleting a server also deletes its backups). Recommended for production: true."
}

variable "cmk_key_vault_key_id" {
  type        = string
  default     = ""
  description = "Key Vault key id for customer-managed encryption at rest. Empty = Microsoft-managed key (still encrypted). CREATE-TIME ONLY; the vault must have purge protection on."
}

variable "cmk_identity_id" {
  type        = string
  default     = ""
  description = "User-assigned identity id used to reach the CMK key. Required when cmk_key_vault_key_id is set."
}
