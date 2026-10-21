# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The label id is the cluster name.

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "Kubernetes minor version, e.g. 1.36. Raising it upgrades the control plane, then the node group and the add-ons that use the default version. EKS upgrades one minor version at a time and never downgrades."

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version such as 1.36."
  }
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC that holds subnet_ids. EKS derives the VPC from the subnets; this is checked against it after the cluster is created."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID such as vpc-0123456789abcdef0."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the control plane network interfaces and the nodes, in at least two availability zones (modules/aws/vpc private_subnet_ids)."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must list at least two subnets in different availability zones."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Expose the Kubernetes API on a public endpoint (limited by public_access_cidrs). The private endpoint is always on. Set false once the operator reaches the API from inside the VPC."
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API endpoint. Narrow this to the operator and CI egress ranges. Ignored when endpoint_public_access is false."

  validation {
    condition     = length(var.public_access_cidrs) > 0 && alltrue([for c in var.public_access_cidrs : can(cidrnetmask(c))])
    error_message = "public_access_cidrs must be a non-empty list of IPv4 CIDRs."
  }
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "ARN of the symmetric KMS key (same region) used for envelope encryption of Kubernetes Secrets. Cannot be changed after the cluster is created."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.secrets_kms_key_arn))
    error_message = "secrets_kms_key_arn must be a KMS key ARN."
  }
}

variable "enabled_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "Control plane log types sent to CloudWatch Logs."

  validation {
    condition     = alltrue([for t in var.enabled_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "enabled_log_types entries must be api, audit, authenticator, controllerManager or scheduler."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 365
  description = "Retention of the control plane log group in days. Must be a value CloudWatch Logs accepts; 0 keeps logs forever."

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN to encrypt the control plane log group. The key policy must let the CloudWatch Logs service use it (modules/aws/kms cloudwatch_logs_enabled = true). Empty uses CloudWatch Logs default encryption."

  validation {
    condition     = var.log_kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  type        = bool
  default     = true
  description = "Give the IAM principal that creates the cluster a cluster-admin access entry. Changing it after creation replaces the cluster. Do not also list that principal in access_entries."
}

variable "access_entries" {
  type = map(object({
    principal_arn     = string
    policy_arn        = optional(string, "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy")
    access_scope_type = optional(string, "cluster")
    namespaces        = optional(list(string), [])
  }))
  default     = {}
  description = "Extra principals that get Kubernetes API access, keyed by a fixed name (e.g. \"platform-admins\"). Each gets one access policy, cluster wide or limited to namespaces."

  validation {
    condition     = alltrue([for e in values(var.access_entries) : contains(["cluster", "namespace"], e.access_scope_type)])
    error_message = "access_entries access_scope_type must be cluster or namespace."
  }

  validation {
    condition     = alltrue([for e in values(var.access_entries) : e.access_scope_type != "namespace" || length(e.namespaces) > 0])
    error_message = "access_entries with access_scope_type = namespace must list at least one namespace."
  }

  validation {
    condition     = alltrue([for e in values(var.access_entries) : can(regex("^arn:aws[a-z-]*:eks::aws:cluster-access-policy/", e.policy_arn))])
    error_message = "access_entries policy_arn must be an EKS access policy ARN (arn:aws:eks::aws:cluster-access-policy/...)."
  }
}

variable "upgrade_support_type" {
  type        = string
  default     = "STANDARD"
  description = "STANDARD: EKS upgrades the control plane automatically when standard support ends. EXTENDED: the version stays on paid extended support."

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.upgrade_support_type)
    error_message = "upgrade_support_type must be STANDARD or EXTENDED."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Block cluster deletion. To destroy the cluster, apply with false first."
}

variable "service_ipv4_cidr" {
  type        = string
  default     = ""
  description = "CIDR for Kubernetes service IPs. Empty lets EKS pick 10.100.0.0/16 or 172.20.0.0/16. Set it when those overlap a network the cluster must reach. Cannot be changed after creation."

  validation {
    condition     = var.service_ipv4_cidr == "" || can(cidrnetmask(var.service_ipv4_cidr))
    error_message = "service_ipv4_cidr must be empty or an IPv4 CIDR."
  }
}

# -----------------------------------------------------------------------------
# Node group
# -----------------------------------------------------------------------------

variable "node_instance_types" {
  type        = list(string)
  default     = ["m7i.xlarge"]
  description = "EC2 instance types for the node group. More than one only helps with SPOT capacity."

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must list at least one instance type."
  }
}

variable "node_capacity_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "ON_DEMAND or SPOT. Changing it replaces the node group."

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_ami_type" {
  type        = string
  default     = "AL2023_x86_64_STANDARD"
  description = "EKS optimized AMI type, e.g. AL2023_x86_64_STANDARD or AL2023_ARM_64_STANDARD (match node_instance_types). Amazon Linux 2023 and Bottlerocket types are accepted. Changing it replaces the node group."

  validation {
    condition     = can(regex("^(AL2023_|BOTTLEROCKET_)", var.node_ami_type)) && !can(regex("WINDOWS", var.node_ami_type))
    error_message = "node_ami_type must be an AL2023_* or Linux BOTTLEROCKET_* AMI type."
  }
}

variable "node_min_size" {
  type        = number
  default     = 3
  description = "Minimum number of nodes."

  validation {
    condition     = var.node_min_size >= 0 && floor(var.node_min_size) == var.node_min_size
    error_message = "node_min_size must be a whole number of 0 or more."
  }
}

variable "node_desired_size" {
  type        = number
  default     = 3
  description = "Number of nodes. Terraform owns this value; there is no cluster autoscaler."

  validation {
    condition     = var.node_desired_size >= 0 && floor(var.node_desired_size) == var.node_desired_size
    error_message = "node_desired_size must be a whole number of 0 or more."
  }
}

variable "node_max_size" {
  type        = number
  default     = 6
  description = "Maximum number of nodes. Also bounds the extra nodes EKS adds during a rolling update."

  validation {
    condition     = var.node_max_size >= 1 && floor(var.node_max_size) == var.node_max_size
    error_message = "node_max_size must be a whole number of 1 or more."
  }
}

variable "node_disk_size_gb" {
  type        = number
  default     = 100
  description = "Size of each node's data volume in GiB (gp3, encrypted). It holds container images and emptyDir volumes."

  validation {
    condition     = var.node_disk_size_gb >= 20 && var.node_disk_size_gb <= 16384
    error_message = "node_disk_size_gb must be between 20 and 16384."
  }
}

variable "node_disk_kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN for node volumes. Empty uses the account's default EBS key. A customer managed key must let the AWSServiceRoleForAutoScaling service-linked role use it and create grants, or nodes fail to launch."

  validation {
    condition     = var.node_disk_kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.node_disk_kms_key_arn))
    error_message = "node_disk_kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "node_labels" {
  type        = map(string)
  default     = {}
  description = "Kubernetes labels added to every node."
}

variable "node_max_unavailable_percentage" {
  type        = number
  default     = 33
  description = "Largest share of nodes, in percent, that may be unavailable during a node group update (1-100)."

  validation {
    condition     = var.node_max_unavailable_percentage >= 1 && var.node_max_unavailable_percentage <= 100
    error_message = "node_max_unavailable_percentage must be between 1 and 100."
  }
}

variable "node_repair_enabled" {
  type        = bool
  default     = true
  description = "Let EKS replace nodes that report unhealthy (node auto repair)."
}

variable "node_additional_policy_arns" {
  type        = map(string)
  default     = {}
  description = "Extra IAM policy ARNs attached to the node role, keyed by a fixed name (e.g. { ecr_pull_through = aws_iam_policy.x.arn }). Keys must be known at plan time; the ARNs may come from the same apply."
}

# -----------------------------------------------------------------------------
# Add-ons
# -----------------------------------------------------------------------------

variable "addons" {
  type = map(object({
    version              = optional(string)
    configuration_values = optional(string)
  }))
  default = {
    "vpc-cni"                               = { configuration_values = "{\"enableNetworkPolicy\":\"true\"}" }
    "eks-pod-identity-agent"                = {}
    "kube-proxy"                            = {}
    "coredns"                               = {}
    "aws-ebs-csi-driver"                    = {}
    "aws-secrets-store-csi-driver-provider" = {}
  }
  description = "EKS managed add-ons keyed by add-on name. version null uses the default version for kubernetes_version. configuration_values is the add-on's JSON config (see aws eks describe-addon-configuration). vpc-cni and eks-pod-identity-agent are installed before the node group, the rest after."
}

variable "ebs_csi_kms_key_arns" {
  type        = list(string)
  default     = []
  description = "KMS key ARNs the EBS CSI driver may use for volumes it creates. Needed only when a StorageClass sets kmsKeyId or the account default EBS key is a customer managed key."

  validation {
    condition     = alltrue([for k in var.ebs_csi_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:", k))])
    error_message = "ebs_csi_kms_key_arns must contain KMS key ARNs."
  }
}
