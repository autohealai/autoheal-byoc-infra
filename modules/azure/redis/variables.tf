# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "resource_group_name" {
  type        = string
  description = "Resource group the cache lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "subnet_id" {
  type        = string
  description = "Dedicated, undelegated subnet to INJECT the cache into (Premium VNet injection). Use modules/azure/vnet output subnet_redis_id. Immutable after create."
}

variable "capacity" {
  type        = number
  default     = 1
  description = "Premium capacity (P-family size): 1=P1 (6GB), 2=P2 (13GB), 3=P3 (26GB), 4=P4 (53GB), 5=P5 (120GB)."

  validation {
    condition     = var.capacity >= 1 && var.capacity <= 5
    error_message = "capacity must be 1-5 (P1-P5)."
  }
}

variable "shard_count" {
  type        = number
  default     = 0
  description = "Redis Cluster shard count (0 = clustering off, a single primary/replica). Premium-only when > 0."
}

variable "redis_version" {
  type        = string
  default     = "6"
  description = "Redis major version."
}

variable "maxmemory_policy" {
  type        = string
  default     = "volatile-lru"
  description = "Eviction policy when maxmemory is hit (e.g. volatile-lru, allkeys-lru, noeviction)."
}

variable "private_static_ip_address" {
  type        = string
  default     = ""
  description = "Pin the cache to a specific IP inside the injected subnet (must be in snet-redis's range). Empty = Azure assigns one. Immutable after create."
}
