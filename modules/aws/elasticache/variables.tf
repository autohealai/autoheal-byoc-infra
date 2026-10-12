# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "vpc_id" {
  type        = string
  description = "VPC the cache security group lives in."
}

variable "vpc_cidr_block" {
  type        = string
  description = "VPC CIDR for the SG egress rule."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet ids for the cache subnet group (modules/aws/vpc output private_subnet_ids)."
}

variable "allowed_sg_ids" {
  type        = list(string)
  default     = []
  description = "Security groups allowed to connect on 6379 (typically the EKS node/cluster SG)."
}

variable "replication_group_id_override" {
  type        = string
  default     = ""
  description = "Force an exact replication group id (<=40 chars). Empty = derive from the label id (truncated to 40)."
}

variable "node_type" {
  type        = string
  default     = "cache.m7g.large"
  description = "Node type (e.g. cache.t4g.small, cache.m7g.large). BYOC uses node-based/provisioned caches."
}

variable "engine_version" {
  type        = string
  default     = "7.1"
  description = "Redis engine version."
}

variable "num_cache_clusters" {
  type        = number
  default     = 2
  description = "Number of nodes. 1 = single node; >= 2 = primary + replica(s) with Multi-AZ automatic failover (prod HA)."
}

variable "snapshot_window" {
  type        = string
  default     = "03:00-04:00"
  description = "Daily snapshot window (UTC)."
}

variable "snapshot_retention_limit" {
  type        = number
  default     = 1
  description = "Days to retain snapshots (0-35)."
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "Apply modifications immediately instead of during the maintenance window."
}
