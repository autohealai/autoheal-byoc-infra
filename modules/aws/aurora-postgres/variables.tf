# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

# Network

variable "vpc_id" {
  type        = string
  description = "VPC the cluster security group is created in."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID (vpc-...)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the DB subnet group (the VPC's data subnets). They must span at least two availability zones."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids needs at least two subnets in different availability zones."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups allowed to connect on the database port (for example the EKS cluster security group)."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDR blocks allowed to connect on the database port."

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : can(cidrnetmask(c))])
    error_message = "allowed_cidr_blocks must contain IPv4 CIDR blocks such as 10.0.0.0/16."
  }
}

# Engine and capacity

variable "engine_version" {
  type        = string
  default     = "16.11"
  description = "Aurora PostgreSQL version, \"major.minor\" (16.11) or major only (16). With a major only value AWS picks the default minor and Terraform keeps \"16\" in state, so automatic minor upgrades never show as drift. The parameter group family follows the major version."

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must look like 16 or 16.11."
  }
}

variable "allow_major_version_upgrade" {
  type        = bool
  default     = false
  description = "Allow a change of engine_version to a new major version. Set it for the upgrade apply only."
}

variable "instance_class" {
  type        = string
  default     = "db.r7g.large"
  description = "Instance class for every instance in the cluster. \"db.serverless\" makes them Serverless v2 instances sized by serverless_min_capacity and serverless_max_capacity."

  validation {
    condition     = startswith(var.instance_class, "db.")
    error_message = "instance_class must be an RDS instance class such as db.r7g.large or db.serverless."
  }
}

variable "serverless_min_capacity" {
  type        = number
  default     = 0.5
  description = "Minimum Aurora capacity units per instance when instance_class is db.serverless. 0 lets idle instances pause."

  validation {
    condition     = var.serverless_min_capacity >= 0 && var.serverless_min_capacity <= 256 && floor(var.serverless_min_capacity * 2) == var.serverless_min_capacity * 2
    error_message = "serverless_min_capacity must be 0-256 in steps of 0.5."
  }
}

variable "serverless_max_capacity" {
  type        = number
  default     = 16
  description = "Maximum Aurora capacity units per instance when instance_class is db.serverless."

  validation {
    condition     = var.serverless_max_capacity >= 1 && var.serverless_max_capacity <= 256 && floor(var.serverless_max_capacity * 2) == var.serverless_max_capacity * 2
    error_message = "serverless_max_capacity must be 1-256 in steps of 0.5."
  }
}

variable "instance_count" {
  type        = number
  default     = 2
  description = "Number of instances: one writer plus readers. Use 2 or more for automatic failover to another availability zone."

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 16 && floor(var.instance_count) == var.instance_count
    error_message = "instance_count must be a whole number from 1 to 16."
  }
}

variable "instance_availability_zones" {
  type        = list(string)
  default     = []
  description = "Optional availability zones for the instances, used in order and repeated (instance N goes to zone N mod length). Empty lets AWS choose. Changing a zone replaces that instance."
}

# Credentials and access

variable "master_username" {
  type        = string
  default     = "pgadmin"
  description = "Master user name."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username)) && lower(var.master_username) != "rdsadmin"
    error_message = "master_username must start with a letter, use only letters, digits and underscores, be at most 63 characters, and not be rdsadmin."
  }
}

variable "master_password" {
  type        = string
  sensitive   = true
  description = "Master user password, 8-128 printable ASCII characters except / \" @ and space. The composition generates it and stores it in Secrets Manager."

  validation {
    condition     = length(var.master_password) >= 8 && length(var.master_password) <= 128 && can(regex("^[!#-.0-?A-~]+$", var.master_password))
    error_message = "master_password must be 8-128 printable ASCII characters and must not contain /, \", @ or a space."
  }
}

variable "port" {
  type        = number
  default     = 5432
  description = "Port the cluster listens on."

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port must be 1150-65535."
  }
}

variable "iam_database_authentication_enabled" {
  type        = bool
  default     = false
  description = "Allow IAM database authentication in addition to passwords."
}

variable "ca_cert_identifier" {
  type        = string
  default     = "rds-ca-rsa2048-g1"
  description = "Certificate authority for the instances' server certificates."

  validation {
    condition     = can(regex("^rds-ca-", var.ca_cert_identifier))
    error_message = "ca_cert_identifier must be an RDS CA such as rds-ca-rsa2048-g1, rds-ca-rsa4096-g1 or rds-ca-ecc384-g1."
  }
}

# Encryption and storage

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for storage, snapshots and Performance Insights."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "storage_type" {
  type        = string
  default     = ""
  description = "Storage configuration. Empty (or \"aurora\") is Aurora Standard; \"aurora-iopt1\" is Aurora I/O-Optimized."

  validation {
    condition     = contains(["", "aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be empty, \"aurora\" or \"aurora-iopt1\"."
  }
}

# Backups, maintenance and deletion

variable "backup_retention_period" {
  type        = number
  default     = 30
  description = "Days to keep automated backups (1-35)."

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period must be a whole number from 1 to 35."
  }
}

variable "preferred_backup_window" {
  type        = string
  default     = "07:00-09:00"
  description = "Daily backup window in UTC (hh24:mi-hh24:mi). Must not overlap the maintenance window."

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", var.preferred_backup_window))
    error_message = "preferred_backup_window must look like 07:00-09:00."
  }
}

variable "preferred_maintenance_window" {
  type        = string
  default     = "sun:09:30-sun:10:30"
  description = "Weekly maintenance window in UTC (ddd:hh24:mi-ddd:hh24:mi), used by the cluster and its instances."

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]$", var.preferred_maintenance_window))
    error_message = "preferred_maintenance_window must look like sun:09:30-sun:10:30."
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
  description = "Apply changes now instead of in the next maintenance window. Some changes restart the database."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Block deletion of the cluster. Set false and apply before a destroy."
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Skip the final snapshot on delete. When false the snapshot is named <cluster>-final-<random hex>."
}

# Monitoring and logs

variable "performance_insights_enabled" {
  type        = bool
  default     = true
  description = "Turn on Performance Insights (Database Insights standard mode) with 7 days of retention, encrypted with kms_key_arn."
}

variable "monitoring_interval" {
  type        = number
  default     = 60
  description = "Enhanced Monitoring interval in seconds. 0 turns it off; otherwise the module creates the monitoring role."

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  default     = ["postgresql"]
  description = "Log types to export to CloudWatch Logs. The module creates each log group first so it controls retention and encryption."

  validation {
    condition     = alltrue([for l in var.enabled_cloudwatch_logs_exports : contains(["postgresql", "instance", "iam-db-auth-error"], l)])
    error_message = "enabled_cloudwatch_logs_exports may contain postgresql, instance and iam-db-auth-error."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 365
  description = "Retention in days for the exported log groups."

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN for the exported log groups. Empty uses CloudWatch Logs default encryption. The key policy must allow the CloudWatch Logs service."

  validation {
    condition     = var.log_kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be empty or a KMS key ARN."
  }
}

# Parameters

variable "cluster_parameters" {
  type        = map(string)
  default     = {}
  description = "Cluster parameter overrides, merged over the module defaults rds.force_ssl = 1 and log_min_duration_statement = 1000."
}

variable "cluster_parameters_pending_reboot" {
  type        = list(string)
  default     = []
  description = "Names of static parameters in cluster_parameters (for example shared_preload_libraries). They are applied with pending-reboot; all others apply immediately."
}
