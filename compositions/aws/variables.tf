# Inputs for the AWS composition. examples/aws/prod/infra/terragrunt.hcl shows a
# typical set. Every building block takes an optional existing_* input: set it to
# use a resource you already have, leave it empty and we create one.

# ---------------------------------------------------------------------------
# Naming and placement
# ---------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Customer or tenant, e.g. 'acme'. First element of every resource name."
}

variable "environment" {
  type        = string
  description = "Lifecycle, e.g. prod, staging, play. Not the region."
}

variable "name" {
  type        = string
  default     = "autoheal"
  description = "Component name; the last element of resource names."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto every resource we create."
}

variable "account_id" {
  type        = string
  description = "AWS account to deploy into. The provider refuses to run with credentials for any other account. Get it with: aws sts get-caller-identity --query Account --output text"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID. Get it with: aws sts get-caller-identity --query Account --output text"
  }
}

variable "region" {
  type        = string
  description = "AWS region, e.g. us-west-2. The region is not part of resource names."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as us-west-2."
  }
}

# ---------------------------------------------------------------------------
# Hostnames and edge
# ---------------------------------------------------------------------------

variable "hostname" {
  type        = string
  description = "The name users open, e.g. autoheal.acme.example."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.hostname))
    error_message = "hostname must be a lowercase DNS name such as autoheal.acme.example."
  }
}

variable "auth_hostname" {
  type        = string
  default     = ""
  description = "Login hostname. Empty means auth.<hostname>."
}

variable "auth_app_hostname" {
  type        = string
  default     = ""
  description = "auth-app hostname. Empty means auth-app.<hostname>."
}

variable "edge_mode" {
  type        = string
  default     = "loadbalancer"
  description = "How traffic reaches the Autoheal proxy: loadbalancer (we create a Network Load Balancer for it), gateway-api, istio, ingress or none. Becomes global.edge.mode."

  validation {
    condition     = contains(["loadbalancer", "gateway-api", "istio", "ingress", "none"], var.edge_mode)
    error_message = "edge_mode must be one of loadbalancer, gateway-api, istio, ingress, none."
  }
}

variable "edge_exposure" {
  type        = string
  default     = "internal"
  description = "Scheme of the edge Network Load Balancer in loadbalancer mode: internal (private subnets, reachable from the VPC and networks routed to it) or internet-facing (public subnets). internet-facing needs edge_allowed_cidr_blocks."

  validation {
    condition     = contains(["internal", "internet-facing"], var.edge_exposure)
    error_message = "edge_exposure must be internal or internet-facing."
  }
}

variable "edge_allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Client CIDRs allowed to reach the edge load balancer on ports 443 and 80. Empty means the VPC CIDR for an internal load balancer; an internet-facing one needs an explicit list (use [\"0.0.0.0/0\"] for a public install)."

  validation {
    condition     = alltrue([for c in var.edge_allowed_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "Every edge_allowed_cidr_blocks entry must be an IPv4 CIDR such as 10.0.0.0/8."
  }
}

variable "edge_address" {
  type        = string
  default     = ""
  description = "Address of the customer's gateway, Istio ingress or Ingress controller, used when edge_mode is not loadbalancer: an IPv4 address (A records) or a DNS name such as a load balancer's (CNAME records). Empty means the records are left to the customer."

  validation {
    condition = var.edge_address == "" || can(cidrhost("${var.edge_address}/32", 0)) || can(regex(
      "^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.edge_address
    ))
    error_message = "edge_address must be an IPv4 address such as 10.50.0.20 or a lowercase DNS name."
  }
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

variable "existing_dns_zone_id" {
  type        = string
  default     = ""
  description = "ID of the Route 53 hosted zone (public or private) that holds the hostnames, e.g. Z0123456789ABCDEFGHIJ. We create records in it, never the zone."

  validation {
    condition     = var.existing_dns_zone_id == "" || can(regex("^Z[A-Z0-9]{1,32}$", var.existing_dns_zone_id))
    error_message = "existing_dns_zone_id must be a Route 53 hosted zone ID such as Z0123456789ABCDEFGHIJ."
  }
}

variable "create_dns_records" {
  type        = bool
  default     = true
  description = "Create records for the three hostnames in existing_dns_zone_id. Set false when DNS is managed outside Route 53; the required_dns_records output then lists the records to create."
}

variable "dns_record_ttl" {
  type        = number
  default     = 300
  description = "TTL in seconds for A and CNAME records. Alias records to the edge load balancer have no TTL."
}

# ---------------------------------------------------------------------------
# Versions and images
# ---------------------------------------------------------------------------

variable "autoheal_version" {
  type        = string
  description = "Autoheal release (the chart version). The runner VMs pull app/runner-go:chart-<autoheal_version> unless runner_image_tag is set."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.-]+)?$", var.autoheal_version))
    error_message = "autoheal_version must be a release version such as 1.0.0."
  }
}

variable "runner_image_repository" {
  type        = string
  default     = ""
  description = "Repository the runner VMs pull runner-go from. Empty means <registry>/app/runner-go: the ECR mirror when there is one, else public.ecr.aws/e4h3h0d9. The VMs retry the pull until the image exists."
}

variable "runner_image_tag" {
  type        = string
  default     = ""
  description = "Tag of the runner-go image. Empty means chart-<autoheal_version>. Changing it rolls the runner VMs."

  validation {
    condition     = can(regex("^([A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?$", var.runner_image_tag))
    error_message = "runner_image_tag must be a valid image tag, or empty."
  }
}

variable "runner_sandbox_image" {
  type        = string
  default     = ""
  description = "Fully qualified sandbox image the runner VMs pre-pull at boot. Empty skips the pre-pull."
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "network_cidr" {
  type        = string
  default     = "10.60.0.0/16"
  description = "CIDR of the VPC we create. Per availability zone: a private subnet for nodes and pods (the first eighth, then the next ones), and small runner, data and public subnets in the upper half. Ignored when existing_network is set."

  validation {
    condition     = can(cidrhost(var.network_cidr, 0)) && tonumber(split("/", var.network_cidr)[1]) >= 16 && tonumber(split("/", var.network_cidr)[1]) <= 19
    error_message = "network_cidr must be an IPv4 CIDR with a prefix between /16 and /19, such as 10.60.0.0/16."
  }
}

variable "availability_zones" {
  type        = list(string)
  default     = []
  description = "Availability zones of the VPC we create, 2 to 4. Empty means the first three zones of the region that need no opt-in. Ignored when existing_network is set."

  validation {
    condition     = length(var.availability_zones) == 0 || (length(var.availability_zones) >= 2 && length(var.availability_zones) <= 4)
    error_message = "availability_zones must list 2 to 4 zones, or be empty."
  }
}

variable "nat_gateway_mode" {
  type        = string
  default     = "per_az"
  description = "NAT gateways of the VPC we create: per_az (one per zone, survives a zone outage), single (one, cheaper) or none (no internet egress; the runner sandboxes and image pulls from public registries then need another path)."

  validation {
    condition     = contains(["per_az", "single", "none"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be per_az, single or none."
  }
}

variable "existing_network" {
  type = object({
    vpc_id = string
    # Nodes, pods and the internal load balancers. One per zone, at least two.
    private_subnet_ids = list(string)
    # Runner VMs. Empty means private_subnet_ids. Needs a route to the internet.
    runner_subnet_ids = optional(list(string), [])
    # Aurora and ElastiCache, when we create them. Empty means private_subnet_ids.
    data_subnet_ids = optional(list(string), [])
    # Needed only for an internet-facing edge load balancer.
    public_subnet_ids = optional(list(string), [])
    # Security group of the cluster's nodes, which the load balancers and the
    # data stores we create must allow. Empty means the EKS cluster security group.
    node_security_group_id = optional(string, "")
  })
  default     = null
  description = "A VPC you already have. Required with existing_eks_cluster_arn. Null means we create the VPC."

  validation {
    condition = var.existing_network == null ? true : (
      can(regex("^vpc-[0-9a-f]+$", var.existing_network.vpc_id)) &&
      length(var.existing_network.private_subnet_ids) >= 2 &&
      alltrue([
        for id in concat(
          var.existing_network.private_subnet_ids,
          var.existing_network.runner_subnet_ids,
          var.existing_network.data_subnet_ids,
          var.existing_network.public_subnet_ids,
        ) : can(regex("^subnet-[0-9a-f]+$", id))
      ]) &&
      (var.existing_network.node_security_group_id == "" || can(regex("^sg-[0-9a-f]+$", var.existing_network.node_security_group_id)))
    )
    error_message = "existing_network needs vpc_id (vpc-...), at least two private_subnet_ids, subnet IDs that look like subnet-..., and node_security_group_id empty or sg-...."
  }
}

variable "private_endpoints_enabled" {
  type        = bool
  default     = false
  description = "Create VPC interface endpoints (private_endpoint_services) in the VPC we create, so pods and nodes reach AWS APIs without the NAT gateway. Each endpoint costs about 7 USD a month per zone. Required with nat_gateway_mode = none. The S3 gateway endpoint is always created. Ignored for a brought network."
}

variable "private_endpoint_services" {
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "sts", "secretsmanager", "kms", "logs", "ssm", "ssmmessages", "ec2messages", "ec2", "eks-auth", "elasticloadbalancing", "bedrock-runtime"]
  description = "Short service names of the interface endpoints to create when private_endpoints_enabled is true."
}

# ---------------------------------------------------------------------------
# Brought resources. One ARN or ID per block; we read the rest from it.
# ---------------------------------------------------------------------------

variable "existing_eks_cluster_arn" {
  type        = string
  default     = ""
  description = "ARN of an EKS cluster you already have, in this account and region. It needs the eks-pod-identity-agent add-on, the Secrets Store CSI driver with the AWS provider (aws-secrets-store-csi-driver-provider add-on) and an AWS Load Balancer Controller (or install_aws_load_balancer_controller in compositions/app). Needs existing_network."

  validation {
    condition     = var.existing_eks_cluster_arn == "" || can(regex("^arn:aws[a-z-]*:eks:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9][A-Za-z0-9_-]*$", var.existing_eks_cluster_arn))
    error_message = "existing_eks_cluster_arn must look like arn:aws:eks:<region>:<account>:cluster/<name>."
  }
}

variable "existing_postgres_arn" {
  type        = string
  default     = ""
  description = "ARN of an Aurora PostgreSQL cluster (arn:aws:rds:<region>:<account>:cluster:<id>) or an RDS for PostgreSQL instance (...:db:<id>) you already have, version 15 or later, port 5432, reachable from the cluster's nodes. Its admin password must be passed as postgres_admin_password. required_datastore_owner_actions lists the security group rule it needs."

  validation {
    condition     = var.existing_postgres_arn == "" || can(regex("^arn:aws[a-z-]*:rds:[a-z0-9-]+:[0-9]{12}:(cluster|db):[a-z][a-z0-9-]*$", var.existing_postgres_arn))
    error_message = "existing_postgres_arn must look like arn:aws:rds:<region>:<account>:cluster:<id> or arn:aws:rds:<region>:<account>:db:<id>."
  }
}

variable "existing_redis_arn" {
  type        = string
  default     = ""
  description = "ARN of an ElastiCache replication group (Valkey or Redis OSS, cluster mode disabled, encryption in transit and AUTH on) you already have, reachable from the cluster's nodes: arn:aws:elasticache:<region>:<account>:replicationgroup:<id>. Pass its AUTH token as redis_auth_token. required_datastore_owner_actions lists the security group rule it needs."

  validation {
    condition     = var.existing_redis_arn == "" || can(regex("^arn:aws[a-z-]*:elasticache:[a-z0-9-]+:[0-9]{12}:replicationgroup:[a-z][a-z0-9-]*$", var.existing_redis_arn))
    error_message = "existing_redis_arn must look like arn:aws:elasticache:<region>:<account>:replicationgroup:<id>."
  }
}

variable "existing_attachments_bucket_arn" {
  type        = string
  default     = ""
  description = "ARN of an S3 bucket you already have for attachments (arn:aws:s3:::<bucket>), in this region. Browser uploads need a CORS rule for https://<hostname>."

  validation {
    condition     = var.existing_attachments_bucket_arn == "" || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.existing_attachments_bucket_arn))
    error_message = "existing_attachments_bucket_arn must look like arn:aws:s3:::<bucket>."
  }
}

variable "existing_artifacts_bucket_arn" {
  type        = string
  default     = ""
  description = "ARN of an S3 bucket you already have for investigation artifacts (arn:aws:s3:::<bucket>), in this region."

  validation {
    condition     = var.existing_artifacts_bucket_arn == "" || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.existing_artifacts_bucket_arn))
    error_message = "existing_artifacts_bucket_arn must look like arn:aws:s3:::<bucket>."
  }
}

variable "existing_kms_key_arn" {
  type        = string
  default     = ""
  description = "ARN of a symmetric KMS key you already have, in this region, used for everything we encrypt. Its key policy must let IAM policies in this account use it and let logs.<region>.amazonaws.com use it for log groups. Empty means we create one key per purpose (eks, data, storage, secrets, logs)."

  validation {
    condition     = var.existing_kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-z0-9-]+$", var.existing_kms_key_arn))
    error_message = "existing_kms_key_arn must look like arn:aws:kms:<region>:<account>:key/<key-id>."
  }
}

variable "existing_registry_url" {
  type        = string
  default     = ""
  description = "Registry and path of an image mirror you already have, e.g. 123456789012.dkr.ecr.us-west-2.amazonaws.com/autoheal. It must hold the images under app/ and external/, the chart's layout. The nodes and runner VMs pull from it with their instance roles when it is ECR in this account. Empty and create_registry = false means images come from the public registry."

  validation {
    condition     = var.existing_registry_url == "" || can(regex("^[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._-]+)*$", var.existing_registry_url))
    error_message = "existing_registry_url must be a registry host with an optional path and no scheme, such as 123456789012.dkr.ecr.us-west-2.amazonaws.com/autoheal."
  }
}

variable "create_registry" {
  type        = bool
  default     = false
  description = "Create an ECR pull-through cache of the public Autoheal registry (public.ecr.aws/e4h3h0d9). Images are copied into this account on first pull, so the install keeps running if the public registry is unreachable. autoheal_values then points the chart's images at it. Ignored when existing_registry_url is set."
}

variable "registry_repository_prefix" {
  type        = string
  default     = ""
  description = "Repository prefix of the ECR pull-through cache we create, 2 to 30 characters. Empty means <namespace>-<environment>-<name>, cut to 30 characters. Unique per account and region."

  validation {
    condition     = var.registry_repository_prefix == "" || can(regex("^[a-z0-9][a-z0-9._/-]{1,29}$", var.registry_repository_prefix))
    error_message = "registry_repository_prefix must be 2 to 30 lowercase letters, digits and ._/-, or empty."
  }
}

variable "redis_enabled" {
  type        = bool
  default     = true
  description = "Use Redis. When true and existing_redis_arn is empty, we create an ElastiCache for Valkey replication group. When false, global.infra.redis and the Redis entries are left out; the current chart version requires Redis, so keep true for a chart install."
}

# ---------------------------------------------------------------------------
# Object storage
# ---------------------------------------------------------------------------

variable "attachments_bucket_name" {
  type        = string
  default     = ""
  description = "Name of the attachments bucket we create. Empty means <namespace>-<environment>-<name>-attachments. S3 names are global across all accounts."
}

variable "artifacts_bucket_name" {
  type        = string
  default     = ""
  description = "Name of the artifacts bucket we create. Empty means <namespace>-<environment>-<name>-artifacts."
}

variable "tenant_bucket_prefix" {
  type        = string
  default     = ""
  description = "Prefix of the per-tenant bucket api-server-go uses for the Git Registry and tool outputs: <prefix><tenant id>. Empty means <namespace>-<environment>-<name>-. 8 to 27 characters: a bucket name is at most 63 and the tenant ID is 36, and the api-server role may use every bucket named <prefix>*. Cannot change after install."

  validation {
    condition = var.tenant_bucket_prefix == "" || (
      can(regex("^[a-z0-9][a-z0-9-]*$", var.tenant_bucket_prefix)) &&
      length(var.tenant_bucket_prefix) >= 8 &&
      length(var.tenant_bucket_prefix) <= 27 &&
      !strcontains(var.tenant_bucket_prefix, "--") &&
      !startswith(var.tenant_bucket_prefix, "sthree-") &&
      !startswith(var.tenant_bucket_prefix, "amzn-s3-demo-")
    )
    error_message = "tenant_bucket_prefix must be 8 to 27 lowercase letters, digits and hyphens, starting with a letter or digit, without -- and not starting with sthree- or amzn-s3-demo-."
  }
}

variable "tenant_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
  description = "Tenant ID of the install. A single-tenant install always uses the default."

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "tenant_id must be a lowercase UUID."
  }
}

variable "create_tenant_bucket" {
  type        = bool
  default     = true
  description = "Create the tenant bucket (<tenant_bucket_prefix><tenant_id>) with the same encryption, versioning and policy as the other buckets. When false, api-server-go creates it at first use and its role gets s3:CreateBucket on the prefix."
}

variable "s3_noncurrent_version_expiration_days" {
  type        = number
  default     = 90
  description = "Days a replaced or deleted object version is kept in the buckets we create before it expires. 0 keeps every version."

  validation {
    condition     = var.s3_noncurrent_version_expiration_days >= 0
    error_message = "s3_noncurrent_version_expiration_days must be 0 or more."
  }
}

variable "s3_access_log_bucket" {
  type        = string
  default     = ""
  description = "Bucket that receives S3 server access logs of the buckets we create. Empty turns access logging off. It must allow the S3 logging service to write."
}

variable "s3_force_destroy" {
  type        = bool
  default     = false
  description = "Let terraform destroy delete the buckets we create with their objects. Only for throwaway installs."
}

# ---------------------------------------------------------------------------
# Secrets Manager
# ---------------------------------------------------------------------------

variable "secrets_name_prefix" {
  type        = string
  default     = ""
  description = "Name prefix of the install secrets we write to Secrets Manager: <prefix><entry>. Empty means <namespace>-<environment>-<name>/. Ends in / or -, so the secrets role's <prefix>* pattern cannot match a longer prefix. Unique per account and region."

  validation {
    condition     = var.secrets_name_prefix == "" || can(regex("^[A-Za-z0-9/_+=.@-]{0,255}[/-]$", var.secrets_name_prefix))
    error_message = "secrets_name_prefix may hold letters, digits and /_+=.@- only, and must end in / or -."
  }
}

variable "runtime_secrets_name_prefix" {
  type        = string
  default     = ""
  description = "Name prefix of the secrets api-server-go creates at runtime for the integration credentials users enter: <prefix>/tenants/<tenant>/... Empty means <namespace>-<environment>-<name>-runtime. Cannot change after install, since existing secrets would no longer be found. Must not overlap secrets_name_prefix: the api-server role may manage every secret under it."

  validation {
    condition = var.runtime_secrets_name_prefix == "" || (
      can(regex("^[A-Za-z0-9_+=.@-]+(/[A-Za-z0-9_+=.@-]+)*$", var.runtime_secrets_name_prefix)) &&
      length(var.runtime_secrets_name_prefix) <= 128 &&
      split("/", var.runtime_secrets_name_prefix)[0] != "tenants"
    )
    error_message = "runtime_secrets_name_prefix must be at most 128 letters, digits and /_+=.@-, with / only between non-empty parts and a first part other than tenants."
  }
}

variable "secrets_recovery_window_in_days" {
  type        = number
  default     = 30
  description = "Days a deleted install secret can be restored (0 deletes at once, else 7-30). A secret in its recovery window blocks a new one with the same name, so a reinstall under the same names within the window fails; use 0 for throwaway installs."

  validation {
    condition     = var.secrets_recovery_window_in_days == 0 || (var.secrets_recovery_window_in_days >= 7 && var.secrets_recovery_window_in_days <= 30)
    error_message = "secrets_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

variable "create_pod_identity_associations" {
  type        = bool
  default     = true
  description = "Create the EKS Pod Identity associations that bind the chart's service accounts to their IAM roles. Set false when the deployer may create roles but not associations: the roles are still created and the required_role_assignments output lists the associations for an administrator."
}

variable "iam_permissions_boundary_arn" {
  type        = string
  default     = ""
  description = "Permissions boundary attached to every IAM role we create, for accounts that require one."

  validation {
    condition     = var.iam_permissions_boundary_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:policy/.+$", var.iam_permissions_boundary_arn))
    error_message = "iam_permissions_boundary_arn must be an IAM policy ARN."
  }
}

variable "service_accounts" {
  type = object({
    namespace     = optional(string, "autoheal")
    secrets       = optional(list(string), ["autoheal-hooks"])
    api_server    = optional(list(string), ["api-server-go"])
    agents_worker = optional(list(string), ["agents-py-http", "agents-py-worker"])
  })
  default     = {}
  description = "Chart service accounts bound to each IAM role. secrets: the pods that read Secrets Manager, which in the chart is only autoheal-hooks (the secrets-sync hook Job and CronJob). api_server and agents_worker: pods that read and write the buckets. Defaults match the chart in namespace autoheal."
}

variable "bedrock_access_enabled" {
  type        = bool
  default     = true
  description = "Let api-server-go and the agents services call Amazon Bedrock (InvokeModel and InvokeModelWithResponseStream) on bedrock_resource_arns, for installs that use Bedrock models."
}

variable "bedrock_resource_arns" {
  type        = list(string)
  default     = []
  description = "Bedrock resources the workloads may invoke. Empty means every foundation model and every inference profile in this account, which cross-region inference needs."
}

variable "create_load_balancer_controller_role" {
  type        = bool
  default     = null
  nullable    = true
  description = "Create the IAM role and Pod Identity association for the AWS Load Balancer Controller (kube-system/aws-load-balancer-controller), limited to registering targets in our target groups. null means true when we create the cluster. A brought cluster usually has its own controller, whose role must allow elasticloadbalancing:RegisterTargets on our target groups."
}

variable "kms_key_administrator_arns" {
  type        = list(string)
  default     = []
  description = "IAM roles or users that administer the KMS keys we create (rotate, disable, schedule deletion) without being able to use them. The account root statement is always present, so IAM policies in this account can also grant access."

  validation {
    condition     = alltrue([for a in var.kms_key_administrator_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", a))])
    error_message = "kms_key_administrator_arns must be IAM role or user ARNs."
  }
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "Kubernetes version of the EKS cluster we create."

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.36."
  }
}

variable "cluster_admin_principal_arns" {
  type        = list(string)
  default     = []
  description = "IAM roles or users granted cluster admin on the EKS cluster we create through access entries, e.g. a break-glass role. The identity that runs the apply is always admin, so do not list it. For IAM Identity Center roles use cluster_admin_sso_permission_sets."

  validation {
    condition     = alltrue([for a in var.cluster_admin_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", a))])
    error_message = "cluster_admin_principal_arns must be IAM role or user ARNs."
  }
}

variable "cluster_admin_sso_permission_sets" {
  type        = list(string)
  default     = []
  description = "IAM Identity Center permission set names granted cluster admin on the EKS cluster we create, e.g. AutohealAdmin. Each must be assigned to this account. The plan looks up its role (AWSReservedSSO_<name>_<suffix> under /aws-reserved/sso.amazonaws.com/), so the random suffix is never copied into a file and a recreated role is picked up on the next apply. Use this instead of cluster_admin_principal_arns for SSO roles."

  validation {
    condition     = alltrue([for n in var.cluster_admin_sso_permission_sets : can(regex("^[A-Za-z0-9_+=,.@-]{1,32}$", n))])
    error_message = "cluster_admin_sso_permission_sets must be permission set names: 1 to 32 letters, digits and _+=,.@- characters."
  }
}

variable "cluster_viewer_principal_arns" {
  type        = list(string)
  default     = []
  description = "IAM roles or users with read-only access to the EKS cluster we create: AmazonEKSViewPolicy across the cluster, which shows workloads and pod logs but not Secrets. For on-call and audit roles."

  validation {
    condition     = alltrue([for a in var.cluster_viewer_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", a))])
    error_message = "cluster_viewer_principal_arns must be IAM role or user ARNs."
  }
}

variable "cluster_viewer_sso_permission_sets" {
  type        = list(string)
  default     = []
  description = "IAM Identity Center permission set names with read-only access to the EKS cluster we create, looked up as in cluster_admin_sso_permission_sets. Same access as cluster_viewer_principal_arns."

  validation {
    condition     = alltrue([for n in var.cluster_viewer_sso_permission_sets : can(regex("^[A-Za-z0-9_+=,.@-]{1,32}$", n))])
    error_message = "cluster_viewer_sso_permission_sets must be permission set names: 1 to 32 letters, digits and _+=,.@- characters."
  }
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the public endpoint of the EKS cluster we create. Empty means no restriction. Ignored when private_cluster_enabled = true."

  validation {
    condition     = alltrue([for c in var.api_server_authorized_ip_ranges : can(cidrhost(c, 0))])
    error_message = "Every api_server_authorized_ip_ranges entry must be an IPv4 CIDR."
  }
}

variable "private_cluster_enabled" {
  type        = bool
  default     = false
  description = "Turn off the public endpoint of the EKS cluster we create. The apply host and the app install must then reach the VPC."
}

variable "eks_node_instance_types" {
  type        = list(string)
  default     = ["m7i.xlarge"]
  description = "Instance types of the managed node group we create."
}

variable "eks_node_capacity_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "Capacity type of the managed node group we create: ON_DEMAND or SPOT."

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.eks_node_capacity_type)
    error_message = "eks_node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "eks_node_count" {
  type        = number
  default     = 3
  description = "Minimum and starting node count of the managed node group we create. One node per zone is the floor for zone resilience."
}

variable "eks_node_max_count" {
  type        = number
  default     = 6
  description = "Maximum node count of the managed node group we create, for a cluster autoscaler. Raised to eks_node_count when lower."
}

variable "eks_node_ami_type" {
  type        = string
  default     = "AL2023_x86_64_STANDARD"
  description = "AMI type of the managed node group we create. Use AL2023_ARM_64_STANDARD with Graviton instance types such as m7g.xlarge."

  validation {
    condition     = can(regex("^(AL2023_|BOTTLEROCKET_)", var.eks_node_ami_type))
    error_message = "eks_node_ami_type must be an Amazon Linux 2023 or Bottlerocket AMI type, such as AL2023_x86_64_STANDARD."
  }
}

variable "eks_node_disk_size_gb" {
  type        = number
  default     = 100
  description = "Root volume size of each node in GiB (gp3, encrypted)."
}

# ---------------------------------------------------------------------------
# Aurora PostgreSQL
# ---------------------------------------------------------------------------

variable "postgres_engine_version" {
  type        = string
  default     = "16.11"
  description = "Aurora PostgreSQL version of the cluster we create. Minor upgrades are applied automatically in the maintenance window."
}

variable "postgres_instance_class" {
  type        = string
  default     = "db.r7g.large"
  description = "Instance class of the Aurora instances we create. db.serverless turns on Aurora Serverless v2 with postgres_serverless_min_capacity and postgres_serverless_max_capacity."
}

variable "postgres_instance_count" {
  type        = number
  default     = 2
  description = "Aurora instances we create: one writer and the rest readers in other zones. 2 or more for a failover target."

  validation {
    condition     = var.postgres_instance_count >= 1 && var.postgres_instance_count <= 15
    error_message = "postgres_instance_count must be between 1 and 15."
  }
}

variable "postgres_serverless_min_capacity" {
  type        = number
  default     = 0.5
  description = "Minimum Aurora capacity units with postgres_instance_class = db.serverless."
}

variable "postgres_serverless_max_capacity" {
  type        = number
  default     = 16
  description = "Maximum Aurora capacity units with postgres_instance_class = db.serverless."
}

variable "postgres_admin_login" {
  type        = string
  default     = "pgadmin"
  description = "Master user of the Aurora cluster we create. Fixed at create time. Ignored for a brought database, whose login is read from it."
}

variable "postgres_backup_retention_days" {
  type        = number
  default     = 30
  description = "Days of automatic Aurora backups to keep (1-35)."

  validation {
    condition     = var.postgres_backup_retention_days >= 1 && var.postgres_backup_retention_days <= 35
    error_message = "postgres_backup_retention_days must be between 1 and 35."
  }
}

variable "postgres_deletion_protection_enabled" {
  type        = bool
  default     = true
  description = "Protect the Aurora cluster we create against deletion. Set false only for throwaway installs."
}

variable "postgres_skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Skip the final snapshot when the Aurora cluster we create is deleted. Only for throwaway installs."
}

variable "postgres_storage_type" {
  type        = string
  default     = ""
  description = "Aurora storage type: empty for Aurora Standard, aurora-iopt1 for I/O-Optimized (cheaper when I/O is more than about a quarter of the database bill)."

  validation {
    condition     = contains(["", "aurora-iopt1"], var.postgres_storage_type)
    error_message = "postgres_storage_type must be empty or aurora-iopt1."
  }
}

# ---------------------------------------------------------------------------
# ElastiCache
# ---------------------------------------------------------------------------

variable "redis_engine_version" {
  type        = string
  default     = "8.2"
  description = "Valkey version of the ElastiCache replication group we create."
}

variable "redis_node_type" {
  type        = string
  default     = "cache.m7g.large"
  description = "Node type of the ElastiCache replication group we create."
}

variable "redis_node_count" {
  type        = number
  default     = 2
  description = "Nodes of the ElastiCache replication group we create: one primary and the rest replicas in other zones. 2 or more turns on Multi-AZ with automatic failover."

  validation {
    condition     = var.redis_node_count >= 1 && var.redis_node_count <= 6
    error_message = "redis_node_count must be between 1 and 6."
  }
}

# ---------------------------------------------------------------------------
# Runner VMs
# ---------------------------------------------------------------------------

variable "runner_node_count" {
  type        = number
  default     = 1
  description = "Number of runner VMs."
}

variable "runner_instance_type" {
  type        = string
  default     = "m7i.xlarge"
  description = "Instance type of the runner VMs. The default matches Autoheal's hosted runners (4 vCPU, 16 GiB)."
}

variable "runner_architecture" {
  type        = string
  default     = "x86_64"
  description = "CPU architecture of runner_instance_type: x86_64 or arm64. The runner and sandbox images must exist for it."

  validation {
    condition     = contains(["x86_64", "arm64"], var.runner_architecture)
    error_message = "runner_architecture must be x86_64 or arm64."
  }
}

variable "runner_root_volume_size_gb" {
  type        = number
  default     = 200
  description = "Root volume size of the runner VMs in GiB. gp3 with 3000 IOPS at any size, the disk speed of Autoheal's hosted runners."
}

variable "runner_max_concurrent_activities" {
  type        = number
  default     = 20
  description = "Activities each runner VM runs at once. 20 matches Autoheal's hosted runners on the default 4 vCPU, 16 GiB size."
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  type        = number
  default     = 365
  description = "Retention of the CloudWatch log groups we create (EKS control plane, VPC flow logs, ElastiCache)."

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value such as 30, 90, 365 or 731."
  }
}

# ---------------------------------------------------------------------------
# Secrets. Pass these as TF_VAR_* pipeline secrets, never in a committed file.
# ---------------------------------------------------------------------------

variable "postgres_admin_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Master password of a brought database (required with existing_postgres_arn). Optional for a cluster we create; empty means we generate one. Stored in Secrets Manager as postgres-admin-password."
}

variable "redis_auth_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "AUTH token of a brought ElastiCache replication group, required with existing_redis_arn. Ignored for one we create, which gets a generated token. Stored in Secrets Manager as redis-access-key."
}

variable "llm_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "LLM provider API key. Stored in Secrets Manager as llm-api-key. Not needed for Bedrock, or with the chart's LLM gateway on (global.llm.gateway), since the gateway holds the provider keys."
}

variable "llm_gateway_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Key of the customer's LLM gateway (global.llm.gateway in the chart), not a provider key. Stored as gateway-api-key, the chart's default for global.llm.gateway.apiKeyVaultEntry. Needed for every gateway kind except custom, as agents-py does not start without it. For a gateway that ignores it, such as Portkey OSS, set any value."
}

variable "llm_gateway_extra_headers" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Extra request headers for the LLM gateway, as a JSON object of strings with at least one header. Stored as gateway-extra-headers, and global.llm.gateway.extraHeadersVaultEntry is suggested in autoheal_values, with an empty apiKeyVaultEntry when llm_gateway_api_key is unset."

  validation {
    condition = var.llm_gateway_extra_headers == "" || try(
      length(jsondecode(var.llm_gateway_extra_headers)) > 0 &&
      alltrue([for v in values(jsondecode(var.llm_gateway_extra_headers)) : v != null && jsonencode(v) == jsonencode(tostring(v))]),
      false,
    )
    error_message = "llm_gateway_extra_headers must be a JSON object with at least one header, each value a string. Leave it empty for no headers."
  }
}

variable "sso_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Client secret of the customer's SSO application. Stored as sso-client-secret."
}

variable "tls_certificate" {
  type = object({
    certificate = string
    private_key = string
  })
  default     = null
  sensitive   = true
  description = "Corporate TLS certificate (PEM, full chain) and private key (PEM) for the three hostnames. Stored as tls-certificate and tls-private-key. The proxy terminates TLS with it in loadbalancer mode."

  # Secrets Manager does not store an empty value, so an empty field would fail
  # the apply halfway. try() because Terraform 1.7 does not short-circuit ||.
  validation {
    condition = var.tls_certificate == null || try(
      startswith(trimspace(var.tls_certificate.certificate), "-----BEGIN CERTIFICATE-----") &&
      can(regex("^-----BEGIN [A-Z ]*PRIVATE KEY-----", trimspace(var.tls_certificate.private_key))),
      false
    )
    error_message = "tls_certificate needs a PEM certificate (full chain) and a PEM private key. Leave it unset when the edge does not serve your own certificate."
  }
}

variable "edge_ca_certificate" {
  type        = string
  default     = ""
  description = "PEM certificate of the private CA that signed tls_certificate. Stored as edge-ca-certificate, and global.edge.tls.caVaultEntry is suggested in autoheal_values so api-server-go trusts it. Needed only when a private CA signed the edge certificate."

  validation {
    condition     = var.edge_ca_certificate == "" || startswith(trimspace(var.edge_ca_certificate), "-----BEGIN CERTIFICATE-----")
    error_message = "edge_ca_certificate must be a PEM certificate."
  }
}

variable "github_app_private_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Private key of the GitHub App, as PEM text. Stored base64-encoded as github-app-private-key, the form the chart reads. The chart reads it only when values-customer.yaml sets api-server-go.secretEnv.GITHUB_APP_PRIVATE_KEY_BASE64 to github-app-private-key."

  validation {
    condition     = var.github_app_private_key == "" || startswith(trimspace(var.github_app_private_key), "-----BEGIN")
    error_message = "github_app_private_key must be PEM text, not base64. Terraform encodes it."
  }
}

variable "github_app_webhook_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Webhook secret of the GitHub App. Stored as github-app-webhook-secret. The chart reads it only when values-customer.yaml sets api-server-go.secretEnv.GITHUB_APP_WEBHOOK_SECRET to github-app-webhook-secret."
}
