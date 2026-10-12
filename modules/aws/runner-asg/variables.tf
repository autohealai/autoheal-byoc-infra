# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The ASG + launch template are named from the label id.

variable "vpc_id" {
  type        = string
  description = "VPC the runner security group lives in (modules/aws/vpc output vpc_id)."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs the ASG launches into. Egress is via the subnets' NAT gateways; instances get no public IP."
}

variable "temporal_host" {
  type        = string
  description = "Temporal frontend as host:port, the internal NLB (e.g. temporal.internal:7233). The runner polls the `runners` namespace here."
}

variable "ecr_registry" {
  type        = string
  description = "ECR registry endpoint for the credential helper (modules/aws/ecr output registry_url), e.g. <account>.dkr.ecr.<region>.amazonaws.com."
}

variable "runner_image" {
  type        = string
  description = "Fully-qualified runner-go image, e.g. <registry>/release/runner-go:<ver>."
}

variable "sandbox_image" {
  type        = string
  description = "Fully-qualified sandbox image pre-pulled on boot, e.g. <registry>/dev/sandbox:latest."
}

variable "ami_id" {
  type        = string
  default     = ""
  description = "AMI to launch. Empty resolves the latest Amazon Linux 2023 arm64 AMI via SSM (match the instance_type architecture)."
}

variable "instance_type" {
  type        = string
  default     = "m7g.xlarge"
  description = "Instance type. Default is Graviton (arm64); change ami_id too if you switch to x86."
}

variable "runner_name" {
  type        = string
  default     = "runner-byoc-eks"
  description = "NAME env the worker registers under."
}

variable "instance_count" {
  type        = number
  default     = 1
  description = "Desired ASG size. Each runner is an independent Temporal worker; scale out by raising this."
}

variable "min_size" {
  type        = number
  default     = 1
  description = "Minimum ASG size."
}

variable "max_size" {
  type        = number
  default     = 3
  description = "Maximum ASG size."
}

variable "max_concurrent_activities" {
  type        = number
  default     = 5
  description = "API_WORKER_MAX_CONCURRENT_ACTIVITIES per runner."
}

variable "root_volume_size_gb" {
  type        = number
  default     = 200
  description = "Root EBS volume size. Holds Docker layers + sandbox dirs + git datasource caches; 30GB proved insufficient, so default large."
}

variable "key_name" {
  type        = string
  default     = ""
  description = "Optional EC2 key pair for break-glass SSH. Empty (default) relies on SSM Session Manager; no inbound port is opened either way."
}
