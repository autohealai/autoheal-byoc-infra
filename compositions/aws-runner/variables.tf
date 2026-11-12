# Inputs for the runner composition. examples/aws/prod/runner/terragrunt.hcl
# shows a typical set. The runner reaches the cluster only through
# temporal_address; nothing here reads the cluster.

# ---------------------------------------------------------------------------
# Naming and placement
# ---------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Customer or tenant, e.g. 'acme'. First element of every resource name. Use the namespace of compositions/aws."
}

variable "environment" {
  type        = string
  description = "Lifecycle, e.g. prod, staging, play. Not the region."
}

variable "name" {
  type        = string
  default     = "autoheal"
  description = "Component name; the middle element of resource names. Resources get a -runner suffix."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto every resource we create, such as the tags a company's policies require on EC2 instances."
}

variable "account_id" {
  type        = string
  description = "AWS account to deploy into, usually the account_id of compositions/aws. The provider refuses to run with credentials for any other account. Get it with: aws sts get-caller-identity --query Account --output text"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID. Get it with: aws sts get-caller-identity --query Account --output text"
  }
}

variable "region" {
  type        = string
  description = "AWS region of subnet_ids, e.g. us-west-2."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as us-west-2."
  }
}

# ---------------------------------------------------------------------------
# Where the runner connects
# ---------------------------------------------------------------------------

variable "temporal_address" {
  type        = string
  description = "Where the runner reaches Temporal, as <host>:<port>: the temporal_address of the runner_load_balancer output of compositions/aws (runner_lb_enabled), e.g. acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:7233. The runner connects as Autoheal's hosted runners do, in plain gRPC with no key, so the host must be private: a private IPv4 address, the DNS name of an internal load balancer in this account and region (looked up at plan), or a name under private_dns_domains."

  validation {
    condition = (
      can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?:[0-9]{1,5}$", var.temporal_address)) &&
      try(tonumber(split(":", var.temporal_address)[1]) >= 1 && tonumber(split(":", var.temporal_address)[1]) <= 65535, false)
    )
    error_message = "temporal_address must be <host>:<port>, such as acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:7233."
  }
}

variable "tool_response_url" {
  type        = string
  default     = ""
  description = "URL the runner posts sandbox tool results to, set as SANDBOX_TOOL_RESPONSE_CALLBACK_URL: the tool_response_url of the runner_load_balancer output of compositions/aws, as on Autoheal's hosted runners. Through the edge on 443 it is https://<app host>/api/v1/internal/sandbox-tool-responses, with tool_response_token_secret and the chart's global.edge.runner.callback.enabled. Empty sends tool results through Temporal, so the runner needs nothing but temporal_address. An http:// URL must be private like temporal_address; https:// may be any host."

  validation {
    condition     = var.tool_response_url == "" || can(regex("^https?://[^\\s/:]+(:[0-9]{1,5})?(/[^\\s]*)?$", var.tool_response_url))
    error_message = "tool_response_url must be empty or an http(s) URL."
  }
}

variable "tool_response_token_secret" {
  type = object({
    arn         = string
    kms_key_arn = string
  })
  default     = null
  description = "Where the runner reads the callback key: the runner_callback_secret output of compositions/aws, the secret entry runner-callback-token and the KMS key that encrypts it. The instance role may read that secret, and decrypt with that key only through Secrets Manager. Before each start the runner reads the key and sends it as SANDBOX_TOOL_RESPONSE_CALLBACK_TOKEN with each tool result; the chart's proxy refuses tool results through the edge without it. The key is never in the user data or this state. Needs an https:// tool_response_url. Null sends no key, as for the runner load balancer on 8083."

  validation {
    condition = var.tool_response_token_secret == null || (
      can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:[A-Za-z0-9/_+=.@-]+$", var.tool_response_token_secret.arn)) &&
      can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.tool_response_token_secret.kms_key_arn))
    )
    error_message = "tool_response_token_secret must be null or the runner_callback_secret output of compositions/aws: a Secrets Manager secret ARN and a KMS key ARN (key/..., not an alias)."
  }
}

variable "private_dns_domains" {
  type        = list(string)
  default     = []
  description = "DNS domains whose names resolve only to private addresses in your network, such as a Route 53 private hosted zone (acme.internal). temporal_address and an http:// tool_response_url may use names under them, for example a record you point at the runner load balancer. Also for a load balancer in another account or region, which the plan cannot look up. Empty allows only private IPv4 addresses and the DNS names of internal load balancers in this account and region."

  validation {
    condition     = alltrue([for d in var.private_dns_domains : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$", d))])
    error_message = "private_dns_domains entries must be lowercase DNS domains without a leading dot, such as acme.internal."
  }
}

variable "sandbox_blocked_destinations" {
  type        = list(string)
  default     = []
  description = "More destinations sandboxes may not reach over TCP, such as the VPC CIDR or the cluster API: IPv4 addresses, IPv4 CIDRs or DNS names. The hosts of temporal_address and of an http:// tool_response_url are always blocked: they take no key, so only the runner itself may use them. An https:// tool_response_url is the edge, which checks the callback key, so sandboxes keep it. Names are looked up when runner-go starts and every 5 minutes after."

  validation {
    condition = alltrue([for d in var.sandbox_blocked_destinations : (
      can(cidrhost(strcontains(d, "/") ? d : "${d}/32", 0)) && !strcontains(d, ":") && (!strcontains(d, "/") || try(cidrsubnet(d, 0, 0) == d, false))
      ) || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", d))
    ])
    error_message = "sandbox_blocked_destinations entries must be IPv4 addresses, IPv4 CIDRs written from their first address (10.60.0.0/16, not 10.60.1.0/16), or lowercase DNS names."
  }
}

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------

variable "chart_version" {
  type        = string
  description = "Autoheal chart version that compositions/app installs, e.g. 1.0.0 (chart_version in versions.hcl in the examples). The runner pulls runner-go:chart-<chart_version> unless runner_image_tag is set, so bump it with the chart."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.chart_version))
    error_message = "chart_version must be a semantic version such as 1.0.0 or 1.1.0-rc.1."
  }
}

variable "runner_image" {
  type        = string
  default     = "public.ecr.aws/e4h3h0d9/app/runner-go"
  description = "Repository the runner instances pull runner-go from, without a tag. The default is the public registry. For a registry you copy the images into, use its repository, such as registry.acme.example/autoheal/app/runner-go, and for a private ECR registry also set ecr_registry_host. The instances retry the pull until the image exists, so it may be pushed after the apply."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/:-]*$", var.runner_image)) && !can(regex("@|:[^/]*$", var.runner_image))
    error_message = "runner_image must be a repository without a tag or digest, such as public.ecr.aws/e4h3h0d9/app/runner-go. Set the tag with runner_image_tag."
  }
}

variable "runner_image_tag" {
  type        = string
  default     = ""
  description = "Tag of the runner-go image. Empty means chart-<chart_version>. Changing it rolls the runner instances."

  validation {
    condition     = can(regex("^([A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?$", var.runner_image_tag))
    error_message = "runner_image_tag must be a valid image tag, or empty."
  }
}

variable "sandbox_image" {
  type        = string
  default     = ""
  description = "Fully qualified sandbox image the runner instances pre-pull at boot. Empty skips the pre-pull."

  validation {
    condition     = var.sandbox_image == "" || can(regex("^[A-Za-z0-9][A-Za-z0-9._/:@-]*$", var.sandbox_image))
    error_message = "sandbox_image must be empty or one image reference, such as public.ecr.aws/e4h3h0d9/app/sandbox:1.2.3, with no spaces."
  }
}

variable "ecr_registry_host" {
  type        = string
  default     = ""
  description = "Private ECR registry the images come from, <account>.dkr.ecr.<region>.amazonaws.com: the registry of global.imageRegistry when it is ECR, such as the pull-through cache of compositions/aws (create_registry). The instance role gets an ecr-pull policy on it, and the instances log in to it for the runner image and the sandbox images runner-go pulls, even when runner_image is public. Empty means the images need no login."

  validation {
    condition     = var.ecr_registry_host == "" || can(regex("^[0-9]{12}\\.dkr\\.ecr(-fips)?\\.[a-z0-9-]+\\.amazonaws\\.com(\\.cn)?$", var.ecr_registry_host))
    error_message = "ecr_registry_host must be empty or an ECR registry host such as 123456789012.dkr.ecr.us-west-2.amazonaws.com."
  }
}

variable "ecr_repository_prefix" {
  type        = string
  default     = ""
  description = "Repository prefix the ecr-pull policy is limited to, such as the registry_repository_prefix of compositions/aws. Empty means every repository in ecr_registry_host. Used only with ecr_registry_host."

  validation {
    condition     = var.ecr_repository_prefix == "" || can(regex("^[a-z0-9][a-z0-9._/-]*[a-z0-9]$", var.ecr_repository_prefix))
    error_message = "ecr_repository_prefix must be empty or an ECR repository prefix such as acme-prod-autoheal, with no trailing slash."
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets for the runner instances, all in one VPC, ideally one per Availability Zone: usually the network.private_subnet_ids output of compositions/aws. They need a route to temporal_address and outbound access to the image registry, Secrets Manager, the git hosts and the endpoints the tools call, directly or through http_proxy. The instances get no public address."

  validation {
    condition     = length(var.subnet_ids) >= 1 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids needs at least one subnet ID (subnet-...)."
  }
}

variable "existing_security_group_id" {
  type        = string
  default     = ""
  description = "ID of a security group you already have for the runner instances, for accounts where a central team owns security groups. When set, we create no security group and add no rule; egress_cidr_blocks and ssh_ingress_cidr_blocks are ignored, and required_network_owner_actions lists what it must allow. Empty means we create the group."

  validation {
    condition     = var.existing_security_group_id == "" || can(regex("^sg-[0-9a-f]+$", var.existing_security_group_id))
    error_message = "existing_security_group_id must be empty or a security group ID (sg-...)."
  }
}

variable "additional_security_group_ids" {
  type        = list(string)
  default     = []
  description = "More security groups for the runner instances, such as one a company requires on every instance."

  validation {
    condition     = alltrue([for s in var.additional_security_group_ids : can(regex("^sg-[0-9a-f]+$", s))])
    error_message = "additional_security_group_ids must be security group IDs (sg-...)."
  }
}

variable "egress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "IPv4 CIDRs the runner instances may reach on any port, on the group we create. Sandboxes need the git hosts, package registries and the APIs the tools call, and the runner needs Temporal and the registry."

  validation {
    condition     = length(var.egress_cidr_blocks) >= 1 && alltrue([for c in var.egress_cidr_blocks : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "egress_cidr_blocks must be one or more IPv4 CIDRs."
  }
}

variable "ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDRs that may reach the runner instances on TCP 22, on the group we create, such as a jump host's subnet. Only useful with key_name. Empty adds no ingress rule."

  validation {
    condition     = alltrue([for c in var.ssh_ingress_cidr_blocks : can(cidrhost(c, 0)) && !strcontains(c, ":") && c != "0.0.0.0/0"])
    error_message = "ssh_ingress_cidr_blocks must be IPv4 CIDRs, and not 0.0.0.0/0."
  }
}

variable "http_proxy" {
  type        = string
  default     = ""
  description = "Outbound HTTP proxy, e.g. http://proxy.acme.example:8080, for subnets whose way out is a proxy. dnf, the Docker daemon (image pulls), the ECR login and runner-go use it, except for no_proxy. Sandboxes do not get it. Empty uses none."

  validation {
    condition     = var.http_proxy == "" || can(regex("^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$", var.http_proxy))
    error_message = "http_proxy must be empty or a URL without credentials, e.g. http://proxy.acme.example:8080."
  }
}

variable "no_proxy" {
  type        = list(string)
  default     = []
  description = "Hosts, domains (.acme.example) and IPv4 CIDRs reached without http_proxy, such as an internal registry, the VPC CIDR or VPC endpoints. The hosts of temporal_address and tool_response_url, the instance metadata address and localhost are always added. Used only with http_proxy."

  validation {
    condition     = alltrue([for h in var.no_proxy : can(regex("^[^\\s,]+$", h))])
    error_message = "no_proxy entries must be single hosts, domains or CIDRs, without spaces or commas."
  }
}

variable "trusted_ca_certificates" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "PEM CA certificates the instances trust on top of the system ones: the private CA of the image registry (a Nexus mirror, for example) or of a proxy that inspects TLS. Each entry holds one or more certificates, such as file(\"nexus-ca.pem\"). dnf, the Docker daemon (image pulls) and the ECR login trust them; runner-go and sandboxes do not get them. Certificates are public, not secrets. Empty adds none."

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
  description = "PEM of your private root CAs, one after another: the same PEM you store in the vault for the chart's global.trust.caVaultEntry. The runner and every sandbox it creates trust them on top of the public CAs. The instances' trust store does not get them; a registry or proxy with a private CA goes in trusted_ca_certificates. Changing it rolls the runner instances. Empty adds none."

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

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "existing_instance_profile_arn" {
  type        = string
  default     = ""
  description = "ARN of an instance profile you already have, for accounts where a central team owns IAM. When set, we create no role, policy or profile, and required_role_policies lists the trust policy and policies its role needs (ECR pull, SSM). Empty means we create them."

  validation {
    condition     = var.existing_instance_profile_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:instance-profile/.+$", var.existing_instance_profile_arn))
    error_message = "existing_instance_profile_arn must be empty or an instance profile ARN (arn:aws:iam::<account>:instance-profile/<name>)."
  }
}

variable "additional_iam_policy_arns" {
  type        = map(string)
  default     = {}
  description = "More managed policies for the instance role we create, keyed by a stable name, e.g. { logs = <policy ARN> }. With existing_instance_profile_arn they are listed in required_role_policies instead."

  validation {
    condition     = alltrue([for a in values(var.additional_iam_policy_arns) : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/.+$", a))])
    error_message = "additional_iam_policy_arns values must be IAM policy ARNs."
  }
}

variable "iam_permissions_boundary_arn" {
  type        = string
  default     = ""
  description = "Permissions boundary attached to the instance role we create, for accounts that require one."

  validation {
    condition     = var.iam_permissions_boundary_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:policy/.+$", var.iam_permissions_boundary_arn))
    error_message = "iam_permissions_boundary_arn must be an IAM policy ARN."
  }
}

variable "ssm_enabled" {
  type        = bool
  default     = true
  description = "Let people reach the runner instances through SSM Session Manager (AmazonSSMManagedInstanceCore on the instance role). Set false where SSM is not used, and use key_name instead."
}

variable "key_name" {
  type        = string
  default     = ""
  description = "EC2 key pair for SSH as ec2-user, for accounts without SSM Session Manager. Pair it with ssh_ingress_cidr_blocks, or a security group that allows TCP 22. Empty adds no key."
}

# ---------------------------------------------------------------------------
# Runner instances
# ---------------------------------------------------------------------------

variable "instance_type" {
  type        = string
  default     = "m7i.xlarge"
  description = "EC2 instance type of the runner instances. Must support architecture. m7i.xlarge (4 vCPU, 16 GiB) matches the size of Autoheal's hosted runners."
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
  description = "AMI ID to pin. Empty picks one with ami_name_filter, or the latest Amazon Linux 2023 AMI when that is empty too. The instances expect Amazon Linux 2023 or an image built from it."

  validation {
    condition     = var.ami_id == "" || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be empty or an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "ami_name_filter" {
  type        = string
  default     = ""
  description = "AMI name pattern for a company image built from Amazon Linux 2023, e.g. *golden-amzn-linux-2023-v*. The newest match from ami_owners is used, so a new image rolls the instances at the next apply. Ignored when ami_id is set."

  validation {
    condition     = can(regex("^[^\\s]*$", var.ami_name_filter))
    error_message = "ami_name_filter must not contain spaces."
  }
}

variable "ami_owners" {
  type        = list(string)
  default     = []
  description = "Accounts that publish the ami_name_filter image (account IDs, or self, amazon). Required with ami_name_filter."

  validation {
    condition     = alltrue([for o in var.ami_owners : can(regex("^([0-9]{12}|self|amazon|aws-marketplace|aws-backup-vault)$", o))])
    error_message = "ami_owners must be account IDs or self, amazon, aws-marketplace, aws-backup-vault."
  }
}

variable "instance_count" {
  type        = number
  default     = 1
  description = "Number of runner instances. Each is an independent Temporal worker. 0 stops them all."

  validation {
    condition     = var.instance_count >= 0 && floor(var.instance_count) == var.instance_count
    error_message = "instance_count must be a whole number of 0 or more."
  }
}

variable "instance_refresh_min_healthy_percentage" {
  type        = number
  default     = 100
  description = "Share of instance_count that stays in service while a change (a new image, AMI or setting) replaces the instances. 100 with instance_refresh_max_healthy_percentage 200 starts each replacement before its old instance stops, so even a single runner keeps polling."

  validation {
    condition     = var.instance_refresh_min_healthy_percentage >= 0 && var.instance_refresh_min_healthy_percentage <= 100
    error_message = "instance_refresh_min_healthy_percentage must be from 0 to 100."
  }
}

variable "instance_refresh_max_healthy_percentage" {
  type        = number
  default     = 200
  description = "Upper limit of instances in service while a change replaces them, as a share of instance_count (100 to 200, at most 100 above instance_refresh_min_healthy_percentage). Above 100 the group launches replacements before it stops the old instances."

  validation {
    condition     = var.instance_refresh_max_healthy_percentage >= 100 && var.instance_refresh_max_healthy_percentage <= 200
    error_message = "instance_refresh_max_healthy_percentage must be from 100 to 200."
  }
}

variable "root_volume_size_gb" {
  type        = number
  default     = 200
  description = "Root volume size of the runner instances in GiB (gp3). Holds Docker layers, sandbox dirs and git datasource caches."

  validation {
    condition     = var.root_volume_size_gb >= 30 && var.root_volume_size_gb <= 16384 && floor(var.root_volume_size_gb) == var.root_volume_size_gb
    error_message = "root_volume_size_gb must be a whole number from 30 to 16384."
  }
}

variable "root_volume_kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key for the root volumes. Empty uses the account's default EBS key. A customer managed key must allow the Auto Scaling service-linked role (AWSServiceRoleForAutoScaling) to use it, or instances fail to launch."

  validation {
    condition     = var.root_volume_kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/.+$", var.root_volume_kms_key_arn))
    error_message = "root_volume_kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "max_concurrent_activities" {
  type        = number
  default     = 20
  description = "Activities each runner instance runs at once. 20 matches Autoheal's hosted runners on the default 4 vCPU, 16 GiB size."

  validation {
    condition     = var.max_concurrent_activities >= 1 && floor(var.max_concurrent_activities) == var.max_concurrent_activities
    error_message = "max_concurrent_activities must be a whole number of 1 or more."
  }
}
