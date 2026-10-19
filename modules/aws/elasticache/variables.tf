# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

# Network

variable "vpc_id" {
  type        = string
  description = "VPC the cache security group is created in."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID (vpc-...)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the cache subnet group (the VPC's data subnets). Use subnets in at least two availability zones for Multi-AZ."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids needs at least one subnet."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups allowed to connect on the cache port (for example the EKS cluster security group)."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDR blocks allowed to connect on the cache port."

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : can(cidrnetmask(c))])
    error_message = "allowed_cidr_blocks must contain IPv4 CIDR blocks such as 10.0.0.0/16."
  }
}

# Engine and nodes

variable "engine" {
  type        = string
  default     = "valkey"
  description = "Cache engine: valkey or redis."

  validation {
    condition     = contains(["valkey", "redis"], var.engine)
    error_message = "engine must be valkey or redis."
  }
}

variable "engine_version" {
  type        = string
  default     = "8.2"
  description = "Engine version as major.minor (Valkey 7.2 or later, Redis OSS 6.2 or later). The parameter group family follows the engine and major version (valkey8, redis7)."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must look like 8.2."
  }
}

variable "node_type" {
  type        = string
  default     = "cache.m7g.large"
  description = "Node type for every node in the group."

  validation {
    condition     = startswith(var.node_type, "cache.")
    error_message = "node_type must be an ElastiCache node type such as cache.m7g.large."
  }
}

variable "num_cache_clusters" {
  type        = number
  default     = 2
  description = "Number of nodes: one primary plus read replicas (1-6). Automatic failover and Multi-AZ need at least 2."

  validation {
    condition     = var.num_cache_clusters >= 1 && var.num_cache_clusters <= 6 && floor(var.num_cache_clusters) == var.num_cache_clusters
    error_message = "num_cache_clusters must be a whole number from 1 to 6."
  }
}

variable "multi_az_enabled" {
  type        = bool
  default     = true
  description = "Place replicas in other availability zones and fail over across zones. Needs automatic_failover_enabled and num_cache_clusters >= 2."
}

variable "automatic_failover_enabled" {
  type        = bool
  default     = true
  description = "Promote a replica when the primary fails. Needs num_cache_clusters >= 2."
}

variable "port" {
  type        = number
  default     = 6379
  description = "Port the cache listens on."

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be 1-65535."
  }
}

variable "parameters" {
  type        = map(string)
  default     = {}
  description = "Parameter overrides for the module's parameter group (for example maxmemory-policy)."
}

# Authentication and encryption

variable "auth_token" {
  type        = string
  sensitive   = true
  description = "AUTH token clients must send, 16-128 characters. Letters, digits and only these symbols: ! & # $ ^ < > -."

  validation {
    condition     = length(var.auth_token) >= 16 && length(var.auth_token) <= 128 && can(regex("^[A-Za-z0-9!&#$^<>-]+$", var.auth_token))
    error_message = "auth_token must be 16-128 characters of letters, digits and the symbols ! & # $ ^ < > -."
  }
}

variable "auth_token_update_strategy" {
  type        = string
  default     = "ROTATE"
  description = "How a changed auth_token is applied. ROTATE accepts both the old and new token until the next change with SET; SET accepts only the new token."

  validation {
    condition     = contains(["ROTATE", "SET"], var.auth_token_update_strategy)
    error_message = "auth_token_update_strategy must be ROTATE or SET."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encryption at rest, including snapshots. Changing it replaces the replication group."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

# Snapshots and maintenance

variable "snapshot_retention_limit" {
  type        = number
  default     = 7
  description = "Days to keep automatic snapshots (0-35). 0 turns snapshots off."

  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35 && floor(var.snapshot_retention_limit) == var.snapshot_retention_limit
    error_message = "snapshot_retention_limit must be a whole number from 0 to 35."
  }
}

variable "snapshot_window" {
  type        = string
  default     = "05:00-06:00"
  description = "Daily snapshot window in UTC (hh24:mi-hh24:mi). Must not overlap the maintenance window."

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", var.snapshot_window))
    error_message = "snapshot_window must look like 05:00-06:00."
  }
}

variable "maintenance_window" {
  type        = string
  default     = "sun:06:30-sun:07:30"
  description = "Weekly maintenance window in UTC (ddd:hh24:mi-ddd:hh24:mi)."

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window))
    error_message = "maintenance_window must look like sun:06:30-sun:07:30."
  }
}

variable "auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "Let AWS apply minor engine upgrades in the maintenance window."
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "Apply changes now instead of in the next maintenance window."
}

# Logs

variable "log_retention_days" {
  type        = number
  default     = 365
  description = "Retention in days for the slow-log and engine-log log groups."

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN for the log groups. Empty uses CloudWatch Logs default encryption. The key policy must allow the CloudWatch Logs service."

  validation {
    condition     = var.log_kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be empty or a KMS key ARN."
  }
}
