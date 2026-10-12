# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "vpc_id" {
  type        = string
  description = "VPC the cluster security group lives in."
}

variable "vpc_cidr_block" {
  type        = string
  description = "VPC CIDR for the SG egress rule."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet ids for the DB subnet group (modules/aws/vpc output private_subnet_ids)."
}

variable "allowed_sg_ids" {
  type        = list(string)
  default     = []
  description = "Security groups allowed to connect on 5432 (typically the EKS node/cluster SG)."
}

variable "engine_version" {
  type        = string
  default     = "16.6"
  description = "Aurora PostgreSQL engine version."
}

variable "database_name" {
  type        = string
  default     = "autoheal"
  description = "Initial database name."
}

variable "master_username" {
  type        = string
  default     = "pgadmin"
  description = "Master username."
}

variable "master_password" {
  type        = string
  sensitive   = true
  description = "Master password. The composition generates one and also seeds it into Secrets Manager; never commit a real value."
}

variable "instance_class" {
  type        = string
  default     = "db.r7g.large"
  description = "Provisioned instance class for the writer/reader. BYOC policy = provisioned (db.r7g.* / db.r8g.*), never db.serverless, for a real install."

  validation {
    condition     = var.instance_class != "db.serverless"
    error_message = "BYOC uses provisioned Aurora; db.serverless is not allowed here."
  }
}

variable "multi_az" {
  type        = bool
  default     = true
  description = "Add a reader instance in a second AZ for HA failover."
}

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Days to retain automated backups."
}

variable "backup_window" {
  type        = string
  default     = "01:00-02:00"
  description = "Preferred backup window (UTC)."
}

variable "maintenance_window" {
  type        = string
  default     = "mon:03:00-mon:04:00"
  description = "Preferred maintenance window (UTC)."
}

variable "deletion_protection" {
  type        = bool
  default     = false
  description = "Enable deletion protection (set true for prod). When false, no final snapshot is taken on destroy."
}

variable "enable_performance_insights" {
  type        = bool
  default     = true
  description = "Enable Performance Insights on the instances."
}
