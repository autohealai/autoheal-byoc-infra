# Input checks: each run breaks one rule and expects the plan to stop on the
# variable validation or the precondition that owns it.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com", reverse_dns_prefix = "com.amazonaws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:role/deployer", user_id = "AROAEXAMPLE:deployer" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-west-2", region = "us-west-2" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}", minified_json = "{}" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0123456789abcdef0", value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_ami" {
    defaults = { architecture = "x86_64", root_device_name = "/dev/xvda" }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["x86_64"] }
  }
  mock_data "aws_vpc_endpoint_service" {
    defaults = {
      service_name       = "com.amazonaws.us-west-2.s3"
      availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
    }
  }
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v1.0.0-eksbuild.1" }
  }
  mock_data "aws_route53_zone" {
    defaults = { name = "acme.example.", private_zone = false }
  }
}

mock_provider "random" {}

variables {
  namespace            = "acme"
  environment          = "prod"
  account_id           = "123456789012"
  region               = "us-west-2"
  hostname             = "autoheal.acme.example"
  autoheal_version     = "2.1.0"
  availability_zones   = ["us-west-2a", "us-west-2b", "us-west-2c"]
  existing_dns_zone_id = "Z0123456789ABCDEFGHIJ"
}

run "bad_account_id" {
  command = plan

  variables {
    account_id = "12345"
  }

  expect_failures = [var.account_id]
}

run "internet_facing_without_cidrs" {
  command = plan

  variables {
    edge_exposure = "internet-facing"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "no_nat_without_endpoints" {
  command = plan

  variables {
    nat_gateway_mode = "none"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "no_nat_without_registry" {
  command = plan

  variables {
    nat_gateway_mode          = "none"
    private_endpoints_enabled = true
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "overlapping_secret_prefixes" {
  command = plan

  variables {
    secrets_name_prefix         = "acme/"
    runtime_secrets_name_prefix = "acme"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "secrets_prefix_without_separator" {
  command = plan

  variables {
    secrets_name_prefix = "acme"
  }

  expect_failures = [var.secrets_name_prefix]
}

run "runtime_prefix_tenants" {
  command = plan

  variables {
    runtime_secrets_name_prefix = "tenants/acme"
  }

  expect_failures = [var.runtime_secrets_name_prefix]
}

run "tenant_prefix_too_long" {
  command = plan

  variables {
    tenant_bucket_prefix = "acme-production-autoheal-ten-"
  }

  expect_failures = [var.tenant_bucket_prefix]
}

run "zone_missing" {
  command = plan

  variables {
    existing_dns_zone_id = ""
  }

  expect_failures = [terraform_data.validate_dns]
}

run "hostname_outside_zone" {
  command = plan

  variables {
    hostname = "autoheal.other.example"
  }

  expect_failures = [terraform_data.validate_dns]
}

run "cname_at_apex" {
  command = plan

  variables {
    hostname     = "acme.example"
    edge_mode    = "gateway-api"
    edge_address = "gw.acme.example"
  }

  expect_failures = [terraform_data.validate_dns]
}

run "arn_in_other_region" {
  command = plan

  variables {
    existing_kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/1234abcd-12ab-44cd-a6ef-1234567890ab"
  }

  override_data {
    target = data.aws_kms_key.existing
    values = { enabled = true, key_spec = "SYMMETRIC_DEFAULT", key_usage = "ENCRYPT_DECRYPT" }
  }

  expect_failures = [terraform_data.validate_arns]
}

run "redis_arn_with_redis_off" {
  command = plan

  variables {
    redis_enabled      = false
    existing_redis_arn = "arn:aws:elasticache:us-west-2:123456789012:replicationgroup:acme-redis"
  }

  override_data {
    target = data.aws_elasticache_replication_group.existing
    values = { primary_endpoint_address = "master.acme-redis.abc.usw2.cache.amazonaws.com", port = 6379, auth_token_enabled = false }
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "brought_cluster_without_network" {
  command = plan

  variables {
    existing_eks_cluster_arn = "arn:aws:eks:us-west-2:123456789012:cluster/acme-eks"
  }

  override_data {
    target = data.aws_eks_cluster.existing
    values = {
      endpoint              = "https://ABCDEF.gr7.us-west-2.eks.amazonaws.com"
      status                = "ACTIVE"
      certificate_authority = [{ data = "Q0E=" }]
      vpc_config            = [{ vpc_id = "vpc-0123456789abcdef0", cluster_security_group_id = "sg-0cluster0000000000" }]
    }
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "bad_permission_set_name" {
  command = plan

  variables {
    cluster_admin_sso_permission_sets = ["Autoheal Admin"]
  }

  expect_failures = [var.cluster_admin_sso_permission_sets]
}

run "permission_set_not_assigned" {
  command = plan

  variables {
    cluster_admin_sso_permission_sets = ["AutohealAdmin"]
  }

  override_data {
    target = data.aws_iam_roles.sso
    values = { arns = [] }
  }

  expect_failures = [data.aws_iam_roles.sso["sso-admin-AutohealAdmin"]]
}

run "admin_and_viewer" {
  command = plan

  variables {
    cluster_admin_principal_arns  = ["arn:aws:iam::123456789012:role/platform"]
    cluster_viewer_principal_arns = ["arn:aws:iam::123456789012:role/platform"]
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "permission_set_also_by_arn" {
  command = plan

  variables {
    cluster_admin_principal_arns      = ["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AutohealAdmin_0123456789abcdef"]
    cluster_admin_sso_permission_sets = ["AutohealAdmin"]
  }

  override_data {
    target = data.aws_iam_roles.sso
    values = { arns = ["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AutohealAdmin_0123456789abcdef"] }
  }

  expect_failures = [terraform_data.validate_inputs]
}
