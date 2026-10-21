# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The NLB is named from the label id, its security group <id>-nlb, and each
# target group <id>-<listener key>-<hash> (all cut to fit AWS limits).

variable "vpc_id" {
  type        = string
  description = "VPC the load balancer, its security group and the target groups live in."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the load balancer gets a node in, one per Availability Zone (private subnets for an internal NLB). Subnets can be added later but removing one replaces the NLB."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids needs at least one subnet."
  }
}

variable "internal" {
  type        = bool
  default     = true
  description = "true for an internal NLB with private addresses only. false makes it internet-facing (public subnets needed)."
}

variable "vpc_cidr_block" {
  type        = string
  description = "IPv4 CIDR of the VPC. The NLB security group allows egress to it on the target and health check ports, where the pod IP targets live."

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0)) && !strcontains(var.vpc_cidr_block, ":")
    error_message = "vpc_cidr_block must be an IPv4 CIDR such as 10.60.0.0/16."
  }
}

variable "listeners" {
  type = map(object({
    port                 = number
    target_port          = optional(number)
    protocol             = optional(string, "TCP")
    deregistration_delay = optional(number, 30)
    health_check = optional(object({
      protocol            = optional(string, "TCP")
      path                = optional(string, "")
      port                = optional(string, "traffic-port")
      interval            = optional(number, 10)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
    }), {})
  }))
  description = "Listeners keyed by a stable name, e.g. temporal. Each gets a TCP listener on port and an ip target group on target_port (default: port). health_check.path applies to HTTP and HTTPS checks only (default /). health_check.port is traffic-port or a port number. The health check timeout is set from the protocol default (6 seconds for HTTP, 10 otherwise) and kept below the interval."

  validation {
    condition     = length(var.listeners) >= 1
    error_message = "listeners needs at least one entry."
  }

  validation {
    condition     = alltrue([for k in keys(var.listeners) : can(regex("^[a-zA-Z0-9_-]+$", k))])
    error_message = "Listener keys may only contain letters, digits, - and _."
  }

  validation {
    condition = alltrue([
      for l in values(var.listeners) :
      l.port >= 1 && l.port <= 65535 && (l.target_port == null ? true : l.target_port >= 1 && l.target_port <= 65535)
    ])
    error_message = "port and target_port must be between 1 and 65535."
  }

  validation {
    condition     = length(distinct([for l in values(var.listeners) : l.port])) == length(var.listeners)
    error_message = "Each listener needs its own port."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.protocol == "TCP"])
    error_message = "Only TCP listeners are supported."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.deregistration_delay >= 0 && l.deregistration_delay <= 3600])
    error_message = "deregistration_delay must be between 0 and 3600 seconds."
  }

  validation {
    condition = alltrue([
      for l in values(var.listeners) :
      contains(["TCP", "HTTP", "HTTPS"], l.health_check.protocol) && (l.health_check.path == "" || (l.health_check.protocol != "TCP" && startswith(l.health_check.path, "/")))
    ])
    error_message = "health_check.protocol must be TCP, HTTP or HTTPS, and health_check.path (HTTP and HTTPS only) must start with /."
  }

  validation {
    condition = alltrue([
      for l in values(var.listeners) :
      l.health_check.port == "traffic-port" || try(can(regex("^[0-9]+$", l.health_check.port)) && tonumber(l.health_check.port) >= 1 && tonumber(l.health_check.port) <= 65535, false)
    ])
    error_message = "health_check.port must be traffic-port or a port number between 1 and 65535."
  }

  validation {
    condition = alltrue([
      for l in values(var.listeners) :
      l.health_check.interval >= 5 && l.health_check.interval <= 300 &&
      l.health_check.healthy_threshold >= 2 && l.health_check.healthy_threshold <= 10 &&
      l.health_check.unhealthy_threshold >= 2 && l.health_check.unhealthy_threshold <= 10
    ])
    error_message = "health_check.interval must be 5 to 300 seconds, and the healthy and unhealthy thresholds 2 to 10."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDRs allowed to connect to every listener port."

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "allowed_cidr_blocks must be IPv4 CIDRs."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups allowed to connect to every listener port, e.g. the runner security group. IDs may be created in the same apply."
}

variable "target_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups of the targets, e.g. the EKS cluster security group the pods use. Each gets an ingress rule from the NLB security group on the target and health check ports. Leave empty when the targets already allow that traffic. IDs may be created in the same apply."
}

variable "cross_zone_enabled" {
  type        = bool
  default     = true
  description = "Spread traffic across targets in all enabled Availability Zones. Off, each NLB node only sends to targets in its own zone, and a zone with no ready pod drops the connections it receives."
}

variable "deletion_protection" {
  type        = bool
  default     = false
  description = "Block deletion of the NLB through the AWS API. When true, set it to false and apply before a destroy."
}

variable "access_logs_bucket" {
  type        = string
  default     = ""
  description = "S3 bucket for NLB access logs. Empty turns access logs off. NLB access logs only cover TLS listeners, so with the TCP listeners of this module the bucket receives nothing."
}

variable "access_logs_prefix" {
  type        = string
  default     = ""
  description = "Key prefix for the access logs in access_logs_bucket. Empty writes to the bucket root."
}
