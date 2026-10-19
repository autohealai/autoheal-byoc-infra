# Plan-time checks with plain messages. Each group is a terraform_data resource
# whose preconditions fail the plan, so an impossible mix of inputs or an
# unsuitable brought resource stops before anything is created. Groups that read
# a brought resource exist only when that resource is brought.
#
# (Input validation blocks cannot refer to other variables on Terraform 1.7, so
# checks that combine inputs live here.)

# --- Combinations of inputs --------------------------------------------------

resource "terraform_data" "validate_inputs" {
  lifecycle {
    precondition {
      condition     = local.create_cluster || !local.create_network
      error_message = "existing_eks_cluster_arn is set but existing_network is not. A brought cluster already sits in a VPC: set existing_network to that VPC, its private subnets and, if the nodes do not use the cluster security group, node_security_group_id."
    }
    precondition {
      condition     = !local.create_edge_lb || var.edge_exposure == "internal" || length(local.create_network ? local.azs : var.existing_network.public_subnet_ids) >= 2
      error_message = "edge_exposure is internet-facing in a brought network, so existing_network.public_subnet_ids needs at least two public subnets in different zones."
    }
    precondition {
      condition     = !local.create_edge_lb || var.edge_exposure == "internal" || length(var.edge_allowed_cidr_blocks) > 0
      error_message = "edge_exposure is internet-facing, so edge_allowed_cidr_blocks is required: the client CIDRs allowed to reach Autoheal, or [\"0.0.0.0/0\"] for a public install."
    }
    precondition {
      condition     = !local.create_network || var.nat_gateway_mode != "none" || (var.private_endpoints_enabled && local.image_registry != "")
      error_message = "nat_gateway_mode is none, so the VPC has no route to the internet. Set private_endpoints_enabled = true so the nodes reach the AWS APIs, and create_registry = true or existing_registry_url so they can pull images. The runner sandboxes then have no internet access."
    }
    precondition {
      condition     = local.create_postgres || nonsensitive(var.postgres_admin_password != "")
      error_message = "existing_postgres_arn is set, so postgres_admin_password is required. AWS cannot return a database's master password; pass it as TF_VAR_postgres_admin_password from the pipeline's secret store."
    }
    precondition {
      condition     = var.existing_redis_arn == "" || var.redis_enabled
      error_message = "existing_redis_arn is set but redis_enabled is false. Set redis_enabled = true to use the brought Redis, or clear existing_redis_arn."
    }
    precondition {
      condition = (
        !startswith("${local.runtime_secrets_prefix}/", local.secrets_prefix) &&
        !startswith(local.secrets_prefix, "${local.runtime_secrets_prefix}/")
      )
      error_message = "secrets_name_prefix (${local.secrets_prefix}) and runtime_secrets_name_prefix (${local.runtime_secrets_prefix}/) overlap. The api-server role may manage every secret under the runtime prefix, so it must not cover the install secrets, and the secrets-sync role must not read runtime secrets. Pick prefixes where neither starts with the other."
    }
    precondition {
      condition     = length(local.tenant_bucket_prefix) <= 27
      error_message = "The tenant bucket prefix ${local.tenant_bucket_prefix} is longer than 27 characters, so <prefix><tenant id> would exceed S3's 63. Set tenant_bucket_prefix, or shorten namespace, environment or name."
    }
    precondition {
      condition     = can(regex("^[a-z0-9][a-z0-9-]*$", local.tenant_bucket_prefix)) && !strcontains(local.tenant_bucket_prefix, "--") && !startswith(local.tenant_bucket_prefix, "sthree-") && !startswith(local.tenant_bucket_prefix, "amzn-s3-demo-")
      error_message = "The tenant bucket prefix ${local.tenant_bucket_prefix} is not a valid S3 name start: lowercase letters, digits and single hyphens only. Set tenant_bucket_prefix."
    }
    precondition {
      condition     = length(local.registry_prefix) >= 2
      error_message = "The ECR repository prefix ${local.registry_prefix} is too short. Set registry_repository_prefix."
    }
  }
}

# --- ARNs in this account and region ----------------------------------------------

resource "terraform_data" "validate_arns" {
  lifecycle {
    precondition {
      condition = alltrue([
        for e in [local.existing.eks, local.existing.postgres, local.existing.redis, local.existing.kms] :
        e == null ? true : e.region == var.region
      ])
      error_message = "Every brought EKS, RDS, ElastiCache and KMS ARN must be in region ${var.region}. Cross-region resources are not supported; use resources in ${var.region} or change region."
    }
    precondition {
      condition = alltrue([
        for e in [local.existing.eks, local.existing.postgres, local.existing.redis] :
        e == null ? true : e.account == var.account_id
      ])
      error_message = "Every brought EKS, RDS and ElastiCache ARN must be in account ${var.account_id}. Run the composition with credentials for the account that owns them."
    }
  }
}

# --- DNS ---------------------------------------------------------------------

resource "terraform_data" "validate_dns" {
  lifecycle {
    precondition {
      condition     = !var.create_dns_records || !(local.create_edge_lb || var.edge_address != "") || var.existing_dns_zone_id != ""
      error_message = "create_dns_records is true but existing_dns_zone_id is empty. Set existing_dns_zone_id to the Route 53 hosted zone that holds ${var.hostname}, or set create_dns_records = false and create the records listed in the required_dns_records output."
    }
    precondition {
      condition = !local.dns_records_created || alltrue([
        for h in values(local.hosts) : h == local.dns_zone_name || endswith(h, ".${local.dns_zone_name}")
      ])
      error_message = "Every hostname must be inside the hosted zone ${local.dns_zone_name}: ${join(", ", values(local.hosts))}. Fix hostname, auth_hostname or auth_app_hostname, or set create_dns_records = false."
    }
    precondition {
      condition     = !local.dns_records_created || local.create_edge_lb || local.edge_address_is_ip || !contains(values(local.hosts), local.dns_zone_name)
      error_message = "A hostname is the zone apex ${local.dns_zone_name}, and edge_address is a DNS name, which needs a CNAME record. A CNAME cannot sit at a zone apex. Use an IPv4 edge_address, a hostname below the apex, or set create_dns_records = false."
    }
  }
}

# --- Brought resources ---------------------------------------------------------

resource "terraform_data" "eks_guard" {
  # A brought cluster without existing_network is reported by validate_inputs.
  count = local.create_cluster || local.create_network ? 0 : 1

  lifecycle {
    precondition {
      condition     = data.aws_eks_cluster.existing[0].vpc_config[0].vpc_id == var.existing_network.vpc_id
      error_message = "EKS cluster ${local.existing.eks.name} is in VPC ${data.aws_eks_cluster.existing[0].vpc_config[0].vpc_id}, not existing_network.vpc_id (${var.existing_network.vpc_id})."
    }
    precondition {
      condition     = data.aws_eks_cluster.existing[0].status == "ACTIVE"
      error_message = "EKS cluster ${local.existing.eks.name} is ${data.aws_eks_cluster.existing[0].status}, not ACTIVE."
    }
  }
}

locals {
  brought_postgres_engine = local.create_postgres ? "" : (
    local.postgres_brought_cluster ? data.aws_rds_cluster.existing[0].engine : data.aws_db_instance.existing[0].engine
  )
  brought_postgres_version = local.create_postgres ? "" : (
    local.postgres_brought_cluster ? data.aws_rds_cluster.existing[0].engine_version : data.aws_db_instance.existing[0].engine_version
  )
  brought_postgres_port = local.create_postgres ? 0 : (
    local.postgres_brought_cluster ? data.aws_rds_cluster.existing[0].port : data.aws_db_instance.existing[0].db_instance_port
  )
}

resource "terraform_data" "postgres_guard" {
  count = local.create_postgres ? 0 : 1

  lifecycle {
    precondition {
      condition     = contains(["aurora-postgresql", "postgres"], local.brought_postgres_engine)
      error_message = "Database ${local.existing.postgres.id} runs ${local.brought_postgres_engine}. Autoheal needs Aurora PostgreSQL or RDS for PostgreSQL."
    }
    precondition {
      condition     = try(tonumber(split(".", local.brought_postgres_version)[0]) >= 15, false)
      error_message = "Database ${local.existing.postgres.id} runs PostgreSQL ${local.brought_postgres_version}. Autoheal needs 15 or later."
    }
    precondition {
      condition     = local.brought_postgres_port == 5432
      error_message = "Database ${local.existing.postgres.id} listens on port ${local.brought_postgres_port}. The chart connects on 5432."
    }
  }
}

resource "terraform_data" "redis_guard" {
  count = var.existing_redis_arn != "" ? 1 : 0

  lifecycle {
    precondition {
      condition     = data.aws_elasticache_replication_group.existing[0].primary_endpoint_address != ""
      error_message = "ElastiCache replication group ${local.existing.redis.id} has no primary endpoint, so it runs in cluster mode. Autoheal needs cluster mode disabled."
    }
    precondition {
      condition     = !data.aws_elasticache_replication_group.existing[0].auth_token_enabled || nonsensitive(var.redis_auth_token != "")
      error_message = "ElastiCache replication group ${local.existing.redis.id} has AUTH on, so redis_auth_token is required. Pass it as TF_VAR_redis_auth_token from the pipeline's secret store."
    }
  }
}

resource "terraform_data" "bucket_guard" {
  for_each = data.aws_s3_bucket.existing

  lifecycle {
    precondition {
      condition     = each.value.bucket_region == var.region
      error_message = "S3 bucket ${each.value.bucket} is in ${each.value.bucket_region}, not ${var.region}."
    }
  }
}

data "aws_kms_key" "existing" {
  count  = local.create_kms ? 0 : 1
  key_id = var.existing_kms_key_arn
}

resource "terraform_data" "kms_guard" {
  count = local.create_kms ? 0 : 1

  lifecycle {
    precondition {
      condition     = data.aws_kms_key.existing[0].enabled && data.aws_kms_key.existing[0].key_spec == "SYMMETRIC_DEFAULT" && data.aws_kms_key.existing[0].key_usage == "ENCRYPT_DECRYPT"
      error_message = "KMS key ${var.existing_kms_key_arn} must be enabled, SYMMETRIC_DEFAULT and ENCRYPT_DECRYPT."
    }
  }
}
