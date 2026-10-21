# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The Auto Scaling group and launch template are named from the label id, the
# IAM role <id>-role, the instance profile <id>-profile and the security group
# <id>-sg.

variable "vpc_id" {
  type        = string
  description = "VPC the runner security group lives in."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the instances launch in, ideally one per Availability Zone. Egress goes through the subnets' NAT gateway; the instances get no public address."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids needs at least one subnet."
  }
}

variable "instance_type" {
  type        = string
  default     = "m7i.xlarge"
  description = "EC2 instance type. Must support var.architecture. m7i.xlarge (4 vCPU, 16 GiB) matches the size of Autoheal's hosted runners."
}

variable "architecture" {
  type        = string
  default     = "x86_64"
  description = "CPU architecture of the AMI and instance type: x86_64 or arm64. The runner and sandbox images must be built for it."

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "ami_id" {
  type        = string
  default     = ""
  description = "AMI ID. Empty uses the latest Amazon Linux 2023 AMI from the public SSM parameter for the architecture, so an apply after AWS publishes a new AMI rolls the instances. Pin an ID to control when that happens. cloud-init expects Amazon Linux 2023 (dnf packages docker and amazon-ecr-credential-helper)."

  validation {
    condition     = var.ami_id == "" || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be empty or an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "root_volume_size_gb" {
  type        = number
  default     = 200
  description = "Root volume size in GiB. Holds Docker layers, sandbox dirs and git datasource caches."

  validation {
    condition     = var.root_volume_size_gb >= 30 && var.root_volume_size_gb <= 16384 && floor(var.root_volume_size_gb) == var.root_volume_size_gb
    error_message = "root_volume_size_gb must be a whole number from 30 to 16384."
  }
}

variable "root_volume_iops" {
  type        = number
  default     = 3000
  description = "gp3 IOPS of the root volume. 3000 is the gp3 baseline and matches Autoheal's hosted runners."

  validation {
    condition     = var.root_volume_iops >= 3000 && var.root_volume_iops <= 16000
    error_message = "root_volume_iops must be from 3000 to 16000."
  }
}

variable "root_volume_throughput" {
  type        = number
  default     = 125
  description = "gp3 throughput of the root volume in MiB/s. 125 is the gp3 baseline."

  validation {
    condition     = var.root_volume_throughput >= 125 && var.root_volume_throughput <= 1000
    error_message = "root_volume_throughput must be from 125 to 1000 MiB/s."
  }
}

variable "root_volume_kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN for the root volume. Empty uses the account's default EBS key. A customer managed key must allow the Auto Scaling service-linked role (AWSServiceRoleForAutoScaling) to use it, or instances fail to launch. The ARN may be created in the same apply."
}

variable "instance_count" {
  type        = number
  default     = 1
  description = "Number of runner instances (min = max = desired). Each runner is an independent Temporal worker; scale out by raising this. 0 stops all runners."

  validation {
    condition     = var.instance_count >= 0 && floor(var.instance_count) == var.instance_count
    error_message = "instance_count must be a whole number of 0 or more."
  }
}

variable "temporal_host" {
  type        = string
  description = "Temporal frontend host:port the runner polls, e.g. the internal NLB: internal-acme-play-autoheal-0123456789.elb.us-west-2.amazonaws.com:7233. May be created in the same apply."

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+:[0-9]{1,5}$", var.temporal_host))
    error_message = "temporal_host must be host:port, e.g. temporal.internal:7233."
  }
}

variable "tool_response_callback_url" {
  type        = string
  description = "URL the runner posts sandbox tool results to, set as SANDBOX_TOOL_RESPONSE_CALLBACK_URL: the api-server-go internal listener, e.g. http://<internal NLB>:8083/api/v1/internal/sandbox-tool-responses. Empty leaves it unset and tool results go through Temporal only."

  validation {
    condition     = var.tool_response_callback_url == "" || can(regex("^https?://[^\\s]+$", var.tool_response_callback_url))
    error_message = "tool_response_callback_url must be empty or an http(s) URL."
  }
}

variable "runner_image" {
  type        = string
  description = "Fully qualified runner-go image, e.g. public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0."

  validation {
    condition     = can(regex("^[^\\s]+$", var.runner_image))
    error_message = "runner_image must be a non-empty image reference without spaces."
  }
}

variable "sandbox_image" {
  type        = string
  default     = ""
  description = "Fully qualified sandbox image to pre-pull on boot. Empty skips the pre-pull."

  validation {
    condition     = can(regex("^[^\\s]*$", var.sandbox_image))
    error_message = "sandbox_image must be an image reference without spaces, or empty."
  }
}

variable "runner_name" {
  type        = string
  description = "NAME env the worker registers under, e.g. runner-byoc-eks."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.runner_name))
    error_message = "runner_name may only contain letters, digits, ., - and _."
  }
}

variable "max_concurrent_activities" {
  type        = number
  default     = 20
  description = "API_WORKER_MAX_CONCURRENT_ACTIVITIES per runner. 20 matches Autoheal's hosted runners on the same 4 vCPU, 16 GiB size."

  validation {
    condition     = var.max_concurrent_activities >= 1 && floor(var.max_concurrent_activities) == var.max_concurrent_activities
    error_message = "max_concurrent_activities must be a whole number of 1 or more."
  }
}

variable "ecr_registry_host" {
  type        = string
  default     = ""
  description = "ECR registry host the images come from, e.g. 123456789012.dkr.ecr.us-west-2.amazonaws.com (the ecr module's registry_host). When set, the instances install amazon-ecr-credential-helper, the host docker CLI pulls from it with the instance role, and runner-go gets a login file refreshed every hour. The role needs pull access: pass the ecr module's pull policy through additional_iam_policy_arns. Empty means the images are public and no login runs."

  validation {
    condition     = var.ecr_registry_host == "" || can(regex("^[0-9]{12}\\.dkr\\.ecr(-fips)?\\.[a-z0-9-]+\\.amazonaws\\.com(\\.cn)?$", var.ecr_registry_host))
    error_message = "ecr_registry_host must be empty or an ECR registry host such as 123456789012.dkr.ecr.us-west-2.amazonaws.com."
  }
}

variable "additional_security_group_ids" {
  type        = list(string)
  default     = []
  description = "More security groups for the instances, next to the module's own egress-only group."
}

variable "egress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "IPv4 CIDRs the instances may reach on any port. Sandboxes need the internet (git hosts, package registries, customer APIs), and the runner needs Temporal, the registry and SSM."

  validation {
    condition     = alltrue([for c in var.egress_cidr_blocks : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "egress_cidr_blocks must be IPv4 CIDRs."
  }
}

variable "additional_iam_policy_arns" {
  type        = map(string)
  default     = {}
  description = "More IAM policies for the instance role, keyed by a stable name, e.g. { ecr-pull = <policy ARN> }. The keys must be known at plan time; the ARNs may be created in the same apply."
}

variable "permissions_boundary_arn" {
  type        = string
  default     = ""
  description = "Permissions boundary policy ARN for the instance role. Empty sets none."
}

variable "instance_refresh_min_healthy_percentage" {
  type        = number
  default     = 50
  description = "Share of instance_count that stays in service during an instance refresh. With one instance, anything below 100 stops it before its replacement starts; set 100 with instance_refresh_max_healthy_percentage above 100 to start the replacement first."

  validation {
    condition     = var.instance_refresh_min_healthy_percentage >= 0 && var.instance_refresh_min_healthy_percentage <= 100
    error_message = "instance_refresh_min_healthy_percentage must be from 0 to 100."
  }
}

variable "instance_refresh_max_healthy_percentage" {
  type        = number
  default     = 100
  description = "Upper limit of instances in service during an instance refresh, as a share of instance_count (100 to 200). Above 100 the group launches replacements before it terminates the old instances."

  validation {
    condition     = var.instance_refresh_max_healthy_percentage >= 100 && var.instance_refresh_max_healthy_percentage <= 200
    error_message = "instance_refresh_max_healthy_percentage must be from 100 to 200."
  }
}
