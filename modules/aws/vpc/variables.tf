# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "cidr_block" {
  type        = string
  description = "IPv4 CIDR of the VPC, e.g. 10.0.0.0/16. All subnet CIDRs must fall inside it."

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be an IPv4 CIDR such as 10.0.0.0/16."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zone names to spread subnets over, e.g. [\"us-west-2a\", \"us-west-2b\", \"us-west-2c\"]. 2 to 6 zones. Each subnet list is indexed in this order."

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 6
    error_message = "availability_zones must list 2 to 6 zones."
  }

  validation {
    condition     = length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "availability_zones must not repeat a zone."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "One CIDR per availability zone for the private subnets (EKS nodes and pods). Size these generously: with the VPC CNI every pod takes a VPC IP."

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "private_subnet_cidrs must contain IPv4 CIDRs."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "One CIDR per availability zone for the public subnets (NAT gateways and internet-facing load balancers). A /24 or smaller is enough."

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "public_subnet_cidrs must contain IPv4 CIDRs."
  }
}

variable "data_subnet_cidrs" {
  type        = list(string)
  default     = []
  description = "Empty, or one CIDR per availability zone for the data subnets (Aurora and ElastiCache). Their route table has no internet route."

  validation {
    condition     = alltrue([for c in var.data_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "data_subnet_cidrs must contain IPv4 CIDRs."
  }
}

variable "nat_gateway_mode" {
  type        = string
  default     = "per_az"
  description = "NAT gateway layout: per_az (one per zone, survives a zone outage), single (one in the first zone, cheaper, zone outage cuts egress) or none (no internet egress; use interface_endpoints for AWS APIs and a pull-through cache or mirror for images)."

  validation {
    condition     = contains(["per_az", "single", "none"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be one of per_az, single, none."
  }
}

variable "cluster_name" {
  type        = string
  default     = ""
  description = "EKS cluster name. When set, public and private subnets get the kubernetes.io/cluster/<name>=shared tag. Data subnets never get it, so load balancers stay out of them."

  validation {
    condition     = var.cluster_name == "" || can(regex("^[0-9A-Za-z][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be empty or a valid EKS cluster name (1-100 letters, digits, '-' or '_', starting with a letter or digit)."
  }
}

variable "flow_logs_enabled" {
  type        = bool
  default     = true
  description = "Send VPC flow logs to a CloudWatch log group created by the module."
}

variable "flow_logs_retention_days" {
  type        = number
  default     = 365
  description = "Retention of the flow log group in days. Must be a value CloudWatch Logs accepts; 0 keeps logs forever."

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be one of 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "flow_logs_kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN to encrypt the flow log group. The key policy must let the CloudWatch Logs service use it (modules/aws/kms cloudwatch_logs_enabled = true). Empty uses CloudWatch Logs default encryption."

  validation {
    condition     = var.flow_logs_kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.flow_logs_kms_key_arn))
    error_message = "flow_logs_kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "flow_logs_traffic_type" {
  type        = string
  default     = "ALL"
  description = "Which traffic the flow logs record: ALL, ACCEPT or REJECT."

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be one of ALL, ACCEPT, REJECT."
  }
}

variable "s3_gateway_endpoint_enabled" {
  type        = bool
  default     = true
  description = "Create an S3 gateway endpoint on the private and data route tables. Free, and keeps S3 traffic off NAT."
}

variable "interface_endpoints" {
  type        = list(string)
  default     = []
  description = "Short AWS service names to create interface endpoints for, e.g. [\"ecr.api\", \"ecr.dkr\", \"sts\", \"logs\"]. They go in the private subnets with private DNS on and share one security group that allows 443 from the VPC CIDR. Use s3_gateway_endpoint_enabled for S3."

  validation {
    condition     = length(distinct(var.interface_endpoints)) == length(var.interface_endpoints)
    error_message = "interface_endpoints must not repeat a service."
  }

  validation {
    condition     = alltrue([for s in var.interface_endpoints : can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", s))])
    error_message = "interface_endpoints entries must be short service names such as ecr.api or bedrock-runtime, not full com.amazonaws.<region>.<service> names."
  }

  validation {
    condition     = !contains(var.interface_endpoints, "s3")
    error_message = "Use s3_gateway_endpoint_enabled for S3 instead of an interface endpoint."
  }
}
