# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The Auto Scaling group and launch template are named from the label id, the
# IAM role <id>-role, the instance profile <id>-profile and the security group
# <id>-sg.

# --- Network ---

variable "vpc_id" {
  type        = string
  description = "VPC of subnet_ids, where the module's security group lives."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID (vpc-...)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the instances launch in, ideally one per Availability Zone. The instances get no public address, so the subnets' routes (a NAT gateway, a proxy, a transit gateway) give them their way out."

  validation {
    condition     = length(var.subnet_ids) >= 1 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids needs at least one subnet ID (subnet-...)."
  }
}

variable "existing_security_group_id" {
  type        = string
  default     = ""
  description = "ID of a security group you already have for the instances. When set, the module creates no security group and adds no rule; egress_cidr_blocks and ssh_ingress_cidr_blocks are ignored. Its owner allows egress to Temporal, the registry, Secrets Manager and what the sandboxes call. Empty means the module creates the group."

  validation {
    condition     = var.existing_security_group_id == "" || can(regex("^sg-[0-9a-f]+$", var.existing_security_group_id))
    error_message = "existing_security_group_id must be empty or a security group ID (sg-...)."
  }
}

variable "additional_security_group_ids" {
  type        = list(string)
  default     = []
  description = "More security groups for the instances, next to the module's group or existing_security_group_id."

  validation {
    condition     = alltrue([for s in var.additional_security_group_ids : can(regex("^sg-[0-9a-f]+$", s))])
    error_message = "additional_security_group_ids must be security group IDs (sg-...)."
  }
}

variable "egress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "IPv4 CIDRs the instances may reach on any port, on the module's security group. Sandboxes need the git hosts, package registries and the APIs the tools call, and the runner needs Temporal, the registry and Secrets Manager."

  validation {
    condition     = alltrue([for c in var.egress_cidr_blocks : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "egress_cidr_blocks must be IPv4 CIDRs."
  }
}

variable "ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDRs that may reach the instances on TCP 22, on the module's security group, such as a jump host. Only useful with key_name. Empty adds no ingress rule."

  validation {
    condition     = alltrue([for c in var.ssh_ingress_cidr_blocks : can(cidrhost(c, 0)) && !strcontains(c, ":") && c != "0.0.0.0/0"])
    error_message = "ssh_ingress_cidr_blocks must be IPv4 CIDRs, and not 0.0.0.0/0."
  }
}

variable "http_proxy" {
  type        = string
  default     = ""
  description = "Outbound HTTP proxy, e.g. http://proxy.acme.example:8080, for subnets whose way out is a proxy. When set, dnf, the Docker daemon (image pulls), the ECR login and runner-go use it, except for no_proxy. Sandboxes do not get it. Empty uses none."

  validation {
    condition     = var.http_proxy == "" || can(regex("^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$", var.http_proxy))
    error_message = "http_proxy must be empty or a URL without credentials, e.g. http://proxy.acme.example:8080."
  }
}

variable "no_proxy" {
  type        = list(string)
  default     = []
  description = "Hosts, domains (.acme.example) and IPv4 CIDRs reached without http_proxy, such as an internal registry or VPC endpoints. The module always adds localhost, 127.0.0.1, the instance metadata address and the hosts of temporal_host and tool_response_callback_url, which the runner reaches directly. Used only with http_proxy."

  validation {
    condition     = alltrue([for h in var.no_proxy : can(regex("^[^\\s,]+$", h))])
    error_message = "no_proxy entries must be single hosts, domains or CIDRs, without spaces or commas."
  }
}

variable "trusted_ca_certificates" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "PEM CA certificates the instances trust on top of the system ones: the private CA of an image registry such as a Nexus mirror, or of a proxy that inspects TLS. Each entry holds one or more certificates. cloud-init adds them to the system trust store before dnf installs packages and before Docker starts, so dnf, the Docker daemon (image pulls) and the ECR login trust them. runner-go and sandboxes do not get them. Certificates are public, not secrets. Empty adds none."

  validation {
    condition = alltrue([
      for c in var.trusted_ca_certificates :
      startswith(trimspace(c), "-----BEGIN CERTIFICATE-----") && endswith(trimspace(c), "-----END CERTIFICATE-----") && !strcontains(c, "PRIVATE KEY")
    ])
    error_message = "Each trusted_ca_certificates entry must be PEM certificates (-----BEGIN CERTIFICATE----- to -----END CERTIFICATE-----), with no private key."
  }
}

variable "custom_ca_certificate" {
  type        = string
  default     = ""
  nullable    = false
  description = "PEM of private root CAs, one after another, that runner-go and every sandbox it creates trust on top of the public CAs: the same PEM as the vault entry of the chart's global.trust.caVaultEntry. Written to /opt/runner-go/ca/custom-ca.pem, the path runner-go reads by default. The host's trust store does not get them; that is trusted_ca_certificates. Changing it rolls the instances. Empty adds none."

  # runner-go stops at startup on anything but certificates it can read, and
  # Go's PEM reader needs each BEGIN and END line on a line of its own.
  validation {
    condition = var.custom_ca_certificate == "" || (
      length(regexall("(?m)^-----BEGIN CERTIFICATE-----[ \\t\\r]*$", var.custom_ca_certificate)) > 0 &&
      length(regexall("-----BEGIN ", var.custom_ca_certificate)) == length(regexall("(?m)^-----BEGIN CERTIFICATE-----[ \\t\\r]*$", var.custom_ca_certificate)) &&
      length(regexall("-----END ", var.custom_ca_certificate)) == length(regexall("(?m)^-----END CERTIFICATE-----[ \\t\\r]*$", var.custom_ca_certificate)) &&
      length(regexall("-----BEGIN ", var.custom_ca_certificate)) == length(regexall("-----END ", var.custom_ca_certificate))
    )
    error_message = "custom_ca_certificate must be empty or PEM certificates only: every -----BEGIN CERTIFICATE----- and -----END CERTIFICATE----- on a line of its own, and no other PEM block, such as a private key or a CRL."
  }
}

# --- Instances ---

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
  description = "AMI ID to pin. Empty picks one with ami_name_filter, or the latest Amazon Linux 2023 AMI from the public SSM parameter for the architecture when that is empty too. cloud-init expects Amazon Linux 2023 or an image built from it (dnf, the docker package)."

  validation {
    condition     = var.ami_id == "" || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be empty or an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "ami_name_filter" {
  type        = string
  default     = ""
  description = "AMI name pattern (wildcards *), e.g. a company's hardened Amazon Linux 2023 image: *golden-amzn-linux-2023-v*. The newest match from ami_owners for the architecture is used. Ignored when ami_id is set. A newer match rolls the instances at the next apply; pin ami_id to control when."

  validation {
    condition     = can(regex("^[^\\s]*$", var.ami_name_filter))
    error_message = "ami_name_filter must not contain spaces."
  }
}

variable "ami_owners" {
  type        = list(string)
  default     = []
  description = "Owners searched with ami_name_filter: account IDs or self, amazon, aws-marketplace. Required with ami_name_filter."

  validation {
    condition     = alltrue([for o in var.ami_owners : can(regex("^([0-9]{12}|self|amazon|aws-marketplace|aws-backup-vault)$", o))])
    error_message = "ami_owners must be account IDs or self, amazon, aws-marketplace, aws-backup-vault."
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

variable "key_name" {
  type        = string
  default     = ""
  description = "EC2 key pair for SSH as ec2-user, for accounts without SSM Session Manager. Pair it with ssh_ingress_cidr_blocks or a security group that allows TCP 22. Empty adds no key."
}

variable "ssm_enabled" {
  type        = bool
  default     = true
  description = "Attach AmazonSSMManagedInstanceCore to the instance role, so people reach the instances through SSM Session Manager. With existing_instance_profile_arn it is listed in required_role_policies instead."
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

# --- Identity ---

variable "existing_instance_profile_arn" {
  type        = string
  default     = ""
  description = "ARN of an instance profile you already have, for accounts where a central team owns IAM. When set, the module creates no role, policy or profile; ssm_enabled, additional_inline_policies and additional_iam_policy_arns are not attached, and required_role_policies lists what the role needs. Empty means the module creates them."

  validation {
    condition     = var.existing_instance_profile_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:instance-profile/.+$", var.existing_instance_profile_arn))
    error_message = "existing_instance_profile_arn must be empty or an instance profile ARN (arn:aws:iam::<account>:instance-profile/<name>)."
  }
}

variable "additional_inline_policies" {
  type        = map(string)
  default     = {}
  description = "More inline policies for the instance role, name => policy JSON, e.g. { logs = <JSON> }. The names must be known at plan time. With existing_instance_profile_arn they are listed in required_role_policies instead."

  validation {
    condition     = !contains(keys(var.additional_inline_policies), "ecr-pull")
    error_message = "additional_inline_policies may not use the name ecr-pull: the module writes it from ecr_registry_host."
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

# --- Runner ---

variable "temporal_host" {
  type        = string
  description = "Temporal frontend host:port the runner polls, set as TEMPORAL_HOST: the internal runner load balancer on 7233 (the temporal_address of compositions/aws's runner_load_balancer output). The runner dials it as Autoheal's hosted runners do, in plain gRPC with no key, so it must be a private address that only the network reaches."

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+:[0-9]{1,5}$", var.temporal_host))
    error_message = "temporal_host must be host:port, e.g. acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:7233."
  }
}

variable "tool_response_callback_url" {
  type        = string
  default     = ""
  description = "URL the runner posts sandbox tool results to, set as SANDBOX_TOOL_RESPONSE_CALLBACK_URL: api-server-go's internal listener behind the runner load balancer (the tool_response_url of compositions/aws's runner_load_balancer output). Empty leaves it unset and tool results go through Temporal only."

  validation {
    condition     = var.tool_response_callback_url == "" || can(regex("^https?://[^\\s/:]+(:[0-9]{1,5})?(/[^\\s]*)?$", var.tool_response_callback_url))
    error_message = "tool_response_callback_url must be empty or an http(s) URL."
  }
}

variable "sandbox_blocked_destinations" {
  type        = list(string)
  default     = []
  description = "More destinations sandboxes may not reach over TCP, on top of the hosts of temporal_host and tool_response_callback_url, which they never reach: IPv4 addresses, IPv4 CIDRs such as 10.60.0.0/16, or DNS names. Names are looked up when runner-go starts and every 5 minutes after. Sandboxes run untrusted code, and the runner load balancer takes no key, so only the runner itself may use it."

  validation {
    condition = alltrue([for d in var.sandbox_blocked_destinations : (
      can(cidrhost(strcontains(d, "/") ? d : "${d}/32", 0)) && !strcontains(d, ":") && (!strcontains(d, "/") || try(cidrsubnet(d, 0, 0) == d, false))
      ) || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", d))
    ])
    error_message = "sandbox_blocked_destinations entries must be IPv4 addresses, IPv4 CIDRs written from their first address (10.60.0.0/16, not 10.60.1.0/16), or lowercase DNS names."
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
  description = "NAME env the worker registers under, e.g. acme-prod-autoheal-runner."

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
  description = "ECR registry host the images come from, e.g. 123456789012.dkr.ecr.us-west-2.amazonaws.com. When set, the instances install amazon-ecr-credential-helper, the host docker CLI pulls from it with the instance role, runner-go gets a login file refreshed every hour, and the role gets the inline policy ecr-pull on it (pull, and the import and create a pull-through cache needs). Empty means the images are public or come from a registry that needs no login."

  validation {
    condition     = var.ecr_registry_host == "" || can(regex("^[0-9]{12}\\.dkr\\.ecr(-fips)?\\.[a-z0-9-]+\\.amazonaws\\.com(\\.cn)?$", var.ecr_registry_host))
    error_message = "ecr_registry_host must be empty or an ECR registry host such as 123456789012.dkr.ecr.us-west-2.amazonaws.com."
  }
}

variable "ecr_repository_prefix" {
  type        = string
  default     = ""
  description = "Repository prefix the ecr-pull policy is limited to, such as the repository prefix of a pull-through cache. Empty means every repository in ecr_registry_host. Used only with ecr_registry_host."

  validation {
    condition     = var.ecr_repository_prefix == "" || can(regex("^[a-z0-9][a-z0-9._/-]*[a-z0-9]$", var.ecr_repository_prefix))
    error_message = "ecr_repository_prefix must be empty or an ECR repository prefix such as acme-prod-autoheal, with no trailing slash."
  }
}
