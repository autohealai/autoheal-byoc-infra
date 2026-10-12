# Inputs for the full AWS BYOC stack. The Terragrunt wrapper in examples/aws-byoc
# supplies these.

# ---------------------------------------------------------------------------
# Identity / naming (null-label; environment = lifecycle, not region)
# ---------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Customer / tenant, e.g. 'avid'. First element of every resource name."
}

variable "environment" {
  type        = string
  description = "Lifecycle: stage | prod | play (NOT region)."
}

variable "name" {
  type        = string
  default     = "autoheal"
  description = "Component name; the middle element of resource names."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto every resource (applied via the aws provider default_tags too)."
}

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "AWS region to deploy into (e.g. us-west-2). Region is implied here, not in the name."
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs to spread subnets across, e.g. ['us-west-2a','us-west-2b','us-west-2c']. One public + one private subnet per AZ."
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  default     = "10.60.0.0/16"
  description = "VPC CIDR block."
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  default     = ""
  description = "EKS cluster name. Empty = derive '<namespace>-<environment>-<name>'. Used for both the cluster and the VPC subnet discovery tags."
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "EKS control-plane version."
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["m7g.large"]
  description = "Instance types for the managed node group."
}

variable "node_desired_size" {
  type        = number
  default     = 3
  description = "Desired node count."
}

variable "node_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count."
}

variable "node_max_size" {
  type        = number
  default     = 10
  description = "Maximum node count."
}

# ---------------------------------------------------------------------------
# PostgreSQL (Aurora, provisioned)
# ---------------------------------------------------------------------------

variable "postgres_engine_version" {
  type        = string
  default     = "16.6"
  description = "Aurora PostgreSQL engine version."
}

variable "postgres_instance_class" {
  type        = string
  default     = "db.r7g.large"
  description = "Aurora instance class. BYOC policy = provisioned (NOT db.serverless)."
}

variable "postgres_multi_az" {
  type        = bool
  default     = true
  description = "Add a reader instance in a second AZ for failover."
}

variable "postgres_deletion_protection" {
  type        = bool
  default     = false
  description = "Block cluster deletion. Leave false for play; set true for stage/prod."
}

# ---------------------------------------------------------------------------
# Redis (ElastiCache, node-based)
# ---------------------------------------------------------------------------

variable "redis_node_type" {
  type        = string
  default     = "cache.m7g.large"
  description = "ElastiCache node type."
}

variable "redis_num_cache_clusters" {
  type        = number
  default     = 2
  description = "Number of nodes. >1 enables automatic failover + Multi-AZ."
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------

variable "ecr_repository_names" {
  type = list(string)
  default = [
    "release/api-server-go",
    "release/runner-go",
    "release/dev-server-go",
    "release/frontend",
    "release/agents-py",
  ]
  description = "ECR repositories to create under the account registry. Match the Autoheal app's image set."
}

# ---------------------------------------------------------------------------
# Secrets Manager
# ---------------------------------------------------------------------------

variable "secret_prefix" {
  type        = string
  default     = ""
  description = "Prefix secrets are created under. Empty = derive 'tenants/<namespace>'. IRSA is scoped to '<prefix>/*'."
}

# ---------------------------------------------------------------------------
# App identity (IRSA)
# ---------------------------------------------------------------------------

variable "federated_service_accounts" {
  type = list(object({
    namespace       = string
    service_account = string
  }))
  default     = [{ namespace = "app", service_account = "autoheal-app" }]
  description = "Kubernetes service accounts federated to the app IRSA role. Set these to match the Autoheal app install's service accounts."
}
