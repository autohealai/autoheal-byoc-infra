# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "cluster_name" {
  type        = string
  default     = ""
  description = "EKS cluster name. Empty derives the label id. Must match the cluster_name passed to modules/aws/vpc (subnet discovery tags)."
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes control-plane version."
}

variable "vpc_id" {
  type        = string
  description = "VPC the cluster and nodes live in (modules/aws/vpc output vpc_id)."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for nodes and the private API endpoint."
}

variable "public_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Public subnet IDs attached to the cluster (for internet-facing load balancers). Nodes stay in private subnets."
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Expose the Kubernetes API server publicly (restrict with public_access_cidrs). Private access is always on."
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API endpoint when endpoint_public_access is true."
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "Control-plane log types shipped to CloudWatch."
}

variable "kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN for envelope-encrypting Kubernetes secrets. Empty disables encryption_config."
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["m7g.large"]
  description = "Instance types for the managed node group."
}

variable "node_capacity_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "ON_DEMAND or SPOT."

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
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

variable "node_labels" {
  type        = map(string)
  default     = {}
  description = "Kubernetes labels applied to node-group nodes."
}

variable "ebs_csi_driver_version" {
  type        = string
  default     = ""
  description = "EBS CSI add-on version. Empty lets EKS pick the default compatible version."
}
