# Derived values shared by the building-block files. Every create-or-bring
# decision is made here from plan-time inputs only (variables, never resource
# attributes), so count and for_each never depend on values known after apply.

data "aws_partition" "current" {}

# Zones of the VPC we create when availability_zones is empty.
data "aws_availability_zones" "available" {
  count = local.create_network && length(var.availability_zones) == 0 ? 1 : 0
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # null-label id used by every module, e.g. acme-prod-autoheal.
  id = lower(join("-", compact([var.namespace, var.environment, var.name])))

  partition  = data.aws_partition.current.partition
  dns_suffix = data.aws_partition.current.dns_suffix

  # --- Create or bring ------------------------------------------------------

  create_network            = var.existing_network == null
  create_cluster            = var.existing_eks_cluster_arn == ""
  create_postgres           = var.existing_postgres_arn == ""
  create_redis              = var.redis_enabled && var.existing_redis_arn == ""
  create_attachments_bucket = var.existing_attachments_bucket_arn == ""
  create_artifacts_bucket   = var.existing_artifacts_bucket_arn == ""
  create_kms                = var.existing_kms_key_arn == ""
  create_registry           = var.existing_registry_url == "" && var.create_registry
  create_edge_lb            = var.edge_mode == "loadbalancer"
  # The controller only binds the edge load balancer's target groups.
  create_lb_controller_role = local.create_edge_lb && (
    var.create_load_balancer_controller_role != null ? var.create_load_balancer_controller_role : local.create_cluster
  )

  redis_enabled = var.redis_enabled || var.existing_redis_arn != ""

  # Brought ARNs split into their parts. An ARN is
  # arn:<partition>:<service>:<region>:<account>:<resource>, so index 3 is the
  # region and index 4 the account. EKS puts the name after "cluster/"; RDS and
  # ElastiCache use "<type>:<id>"; S3 has no region or account.
  existing = {
    eks = local.create_cluster ? null : {
      name    = split("/", var.existing_eks_cluster_arn)[1]
      region  = split(":", var.existing_eks_cluster_arn)[3]
      account = split(":", var.existing_eks_cluster_arn)[4]
    }
    postgres = local.create_postgres ? null : {
      kind    = split(":", var.existing_postgres_arn)[5]
      id      = split(":", var.existing_postgres_arn)[6]
      region  = split(":", var.existing_postgres_arn)[3]
      account = split(":", var.existing_postgres_arn)[4]
    }
    redis = var.existing_redis_arn == "" ? null : {
      id      = split(":", var.existing_redis_arn)[6]
      region  = split(":", var.existing_redis_arn)[3]
      account = split(":", var.existing_redis_arn)[4]
    }
    attachments_bucket = local.create_attachments_bucket ? "" : split(":", var.existing_attachments_bucket_arn)[5]
    artifacts_bucket   = local.create_artifacts_bucket ? "" : split(":", var.existing_artifacts_bucket_arn)[5]
    kms = local.create_kms ? null : {
      region  = split(":", var.existing_kms_key_arn)[3]
      account = split(":", var.existing_kms_key_arn)[4]
    }
  }

  # --- Hostnames ------------------------------------------------------------

  hosts = {
    app     = var.hostname
    auth    = var.auth_hostname != "" ? var.auth_hostname : "auth.${var.hostname}"
    authApp = var.auth_app_hostname != "" ? var.auth_app_hostname : "auth-app.${var.hostname}"
  }

  # --- Names ----------------------------------------------------------------

  attachments_bucket_create_name = var.attachments_bucket_name != "" ? var.attachments_bucket_name : "${local.id}-attachments"
  artifacts_bucket_create_name   = var.artifacts_bucket_name != "" ? var.artifacts_bucket_name : "${local.id}-artifacts"

  # api-server-go names the tenant bucket <prefix><tenant id>.
  tenant_bucket_prefix = var.tenant_bucket_prefix != "" ? var.tenant_bucket_prefix : "${local.id}-"
  tenant_bucket        = "${local.tenant_bucket_prefix}${var.tenant_id}"

  # Install secrets are <secrets_prefix><entry>. api-server-go names runtime
  # secrets <runtime_secrets_prefix>/tenants/<tenant>/..., so that prefix has no
  # trailing slash.
  secrets_prefix         = var.secrets_name_prefix != "" ? var.secrets_name_prefix : "${local.id}/"
  runtime_secrets_prefix = var.runtime_secrets_name_prefix != "" ? var.runtime_secrets_name_prefix : "${local.id}-runtime"

  secret_arn_base = "arn:${local.partition}:secretsmanager:${var.region}:${var.account_id}:secret:"

  registry_prefix = var.registry_repository_prefix != "" ? var.registry_repository_prefix : trimsuffix(substr(local.id, 0, 30), "-")

  # --- Network --------------------------------------------------------------

  azs = length(var.availability_zones) > 0 ? var.availability_zones : (
    local.create_network ? slice(data.aws_availability_zones.available[0].names, 0, min(3, length(data.aws_availability_zones.available[0].names))) : []
  )

  # Subnet layout of the VPC we create. For a /16: private /19s from the bottom
  # (10.60.0.0/19, 10.60.32.0/19, ...), then /24s in the upper half for the
  # data stores (10.60.136.0/24, ...) and the public subnets
  # (10.60.144.0/24, ...). Keep the offsets: changing one replaces the subnets
  # of existing installs and everything in them.
  created_subnets = {
    private = [for i, az in local.azs : cidrsubnet(var.network_cidr, 3, i)]
    data    = [for i, az in local.azs : cidrsubnet(var.network_cidr, 8, 136 + i)]
    public  = [for i, az in local.azs : cidrsubnet(var.network_cidr, 8, 144 + i)]
  }

  vpc_id         = local.create_network ? module.vpc[0].vpc_id : var.existing_network.vpc_id
  vpc_cidr_block = local.create_network ? module.vpc[0].vpc_cidr_block : data.aws_vpc.existing[0].cidr_block

  private_subnet_ids = local.create_network ? module.vpc[0].private_subnet_ids : var.existing_network.private_subnet_ids
  public_subnet_ids  = local.create_network ? module.vpc[0].public_subnet_ids : var.existing_network.public_subnet_ids
  data_subnet_ids = local.create_network ? module.vpc[0].data_subnet_ids : (
    length(var.existing_network.data_subnet_ids) > 0 ? var.existing_network.data_subnet_ids : var.existing_network.private_subnet_ids
  )

  # --- KMS ------------------------------------------------------------------

  # One key per purpose, or the brought key for all of them.
  #   eks      Kubernetes Secrets envelope encryption
  #   data     Aurora storage, Performance Insights and ElastiCache at rest
  #   storage  the S3 buckets
  #   secrets  the install secrets in Secrets Manager
  #   logs     the CloudWatch log groups
  kms_purposes = ["eks", "data", "storage", "secrets", "logs"]
  kms_key_arns = {
    for k in local.kms_purposes : k => (local.create_kms ? module.kms[k].key_arn : var.existing_kms_key_arn)
  }

  # --- Facts gathered from created or brought blocks -------------------------

  # The cluster we create is named after the install id, which the VPC also
  # needs for its subnet tags before the cluster exists.
  cluster_create_name = local.id
  cluster_name        = local.create_cluster ? module.eks[0].cluster_name : local.existing.eks.name
  cluster_endpoint    = local.create_cluster ? module.eks[0].cluster_endpoint : data.aws_eks_cluster.existing[0].endpoint
  cluster_ca_certificate = local.create_cluster ? module.eks[0].cluster_certificate_authority_data : (
    data.aws_eks_cluster.existing[0].certificate_authority[0].data
  )
  cluster_security_group_id = local.create_cluster ? module.eks[0].cluster_security_group_id : (
    data.aws_eks_cluster.existing[0].vpc_config[0].cluster_security_group_id
  )

  # Pods run with the node security group (no security groups for pods), so the
  # load balancers and data stores allow it.
  node_security_group_id = (
    !local.create_network && try(var.existing_network.node_security_group_id, "") != ""
    ? var.existing_network.node_security_group_id
    : local.cluster_security_group_id
  )

  postgres_brought_cluster = !local.create_postgres && try(local.existing.postgres.kind, "") == "cluster"
  postgres_host = local.create_postgres ? module.postgres[0].endpoint : (
    local.postgres_brought_cluster ? data.aws_rds_cluster.existing[0].endpoint : data.aws_db_instance.existing[0].address
  )
  postgres_admin_login = local.create_postgres ? module.postgres[0].master_username : (
    local.postgres_brought_cluster ? data.aws_rds_cluster.existing[0].master_username : data.aws_db_instance.existing[0].master_username
  )

  redis_host = !local.redis_enabled ? "" : (
    local.create_redis ? module.redis[0].primary_endpoint_address : data.aws_elasticache_replication_group.existing[0].primary_endpoint_address
  )
  redis_port = !local.redis_enabled ? 0 : (
    local.create_redis ? module.redis[0].port : data.aws_elasticache_replication_group.existing[0].port
  )

  # Listed in the required_datastore_owner_actions output. We change no security
  # group of a brought data store, so its owner lets the pods in.
  datastore_owner_actions = concat(
    local.create_postgres ? [] : [
      "A security group rule on database ${local.existing.postgres.id} allowing TCP 5432 from ${local.node_security_group_id}, the security group the cluster's pods run with",
    ],
    local.create_redis || !local.redis_enabled ? [] : [
      "A security group rule on ElastiCache replication group ${local.existing.redis.id} allowing TCP ${local.redis_port} from ${local.node_security_group_id}, the security group the cluster's pods run with",
    ],
  )

  attachments_bucket = local.create_attachments_bucket ? module.attachments_bucket[0].bucket_id : local.existing.attachments_bucket
  artifacts_bucket   = local.create_artifacts_bucket ? module.artifacts_bucket[0].bucket_id : local.existing.artifacts_bucket

  # ARNs built from plan-time names, so the IAM policies need no bucket attribute.
  bucket_arns = {
    attachments = "arn:${local.partition}:s3:::${local.create_attachments_bucket ? local.attachments_bucket_create_name : local.existing.attachments_bucket}"
    artifacts   = "arn:${local.partition}:s3:::${local.create_artifacts_bucket ? local.artifacts_bucket_create_name : local.existing.artifacts_bucket}"
    tenant      = "arn:${local.partition}:s3:::${local.tenant_bucket_prefix}*"
  }

  # Registry the chart pulls from, as host/path, or "" for the public registry.
  # An ECR registry host is known at plan time.
  ecr_registry_host = "${var.account_id}.dkr.ecr.${var.region}.${local.dns_suffix}"
  # The public Autoheal registry is public.ecr.aws/<namespace>. The pull-through
  # cache keeps that path under <prefix>/, so the namespace is passed to the
  # ecr module from here rather than taken from its default.
  public_registry_namespace = "e4h3h0d9"
  image_registry = (
    var.existing_registry_url != "" ? var.existing_registry_url :
    local.create_registry ? "${local.ecr_registry_host}/${local.registry_prefix}/${local.public_registry_namespace}" : ""
  )

  # --- DNS ------------------------------------------------------------------

  dns_zone_name = var.existing_dns_zone_id == "" ? "" : lower(trimsuffix(data.aws_route53_zone.this[0].name, "."))

  # Records are created when there is a zone and something to point at: the edge
  # load balancer we create, or edge_address in the other modes.
  dns_records_created = var.create_dns_records && var.existing_dns_zone_id != "" && (local.create_edge_lb || var.edge_address != "")
}
