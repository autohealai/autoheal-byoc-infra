# Case 2: the customer brings everything, and the hybrid case: a brought network
# with everything else created. Brought resources are read through data sources,
# mocked below with values that pass every guard; each failure run overrides one
# of them to show its guard stops the plan.

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
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.20.0.0/16" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:role/deployer" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      endpoint              = "https://ABCDEF.gr7.us-west-2.eks.amazonaws.com"
      status                = "ACTIVE"
      certificate_authority = [{ data = "Q0E=" }]
      vpc_config = [{
        vpc_id                    = "vpc-0123456789abcdef0"
        cluster_security_group_id = "sg-0cluster0000000000"
        subnet_ids                = ["subnet-0a", "subnet-0b"]
        security_group_ids        = []
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
      }]
    }
  }
  mock_data "aws_rds_cluster" {
    defaults = {
      endpoint        = "acme-pg.cluster-abc.us-west-2.rds.amazonaws.com"
      master_username = "pgadmin"
      engine          = "aurora-postgresql"
      engine_version  = "16.6"
      port            = 5432
    }
  }
  mock_data "aws_db_instance" {
    defaults = {
      address          = "acme-pg.abc.us-west-2.rds.amazonaws.com"
      master_username  = "pgadmin"
      engine           = "postgres"
      engine_version   = "17.2"
      db_instance_port = 5432
    }
  }
  mock_data "aws_elasticache_replication_group" {
    defaults = {
      primary_endpoint_address = "master.acme-redis.abc.usw2.cache.amazonaws.com"
      port                     = 6379
      auth_token_enabled       = true
    }
  }
  mock_data "aws_s3_bucket" {
    defaults = { bucket_region = "us-west-2" }
  }
  mock_data "aws_kms_key" {
    defaults = { enabled = true, key_spec = "SYMMETRIC_DEFAULT", key_usage = "ENCRYPT_DECRYPT" }
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

  existing_network = {
    vpc_id             = "vpc-0123456789abcdef0"
    private_subnet_ids = ["subnet-0a", "subnet-0b", "subnet-0c"]
  }
  existing_eks_cluster_arn        = "arn:aws:eks:us-west-2:123456789012:cluster/acme-eks"
  existing_postgres_arn           = "arn:aws:rds:us-west-2:123456789012:cluster:acme-pg"
  existing_redis_arn              = "arn:aws:elasticache:us-west-2:123456789012:replicationgroup:acme-redis"
  existing_attachments_bucket_arn = "arn:aws:s3:::acme-attachments"
  existing_artifacts_bucket_arn   = "arn:aws:s3:::acme-artifacts"
  existing_kms_key_arn            = "arn:aws:kms:us-west-2:123456789012:key/1234abcd-12ab-44cd-a6ef-1234567890ab"
  existing_registry_url           = "123456789012.dkr.ecr.us-west-2.amazonaws.com/autoheal"
  postgres_admin_password         = "brought-admin-password"
  redis_auth_token                = "brought-redis-token"
}

run "everything_brought" {
  command = plan

  assert {
    condition = (
      length(module.vpc) == 0 && length(module.eks) == 0 && length(module.postgres) == 0 &&
      length(module.redis) == 0 && length(module.kms) == 0 && length(module.ecr) == 0 &&
      length(module.attachments_bucket) == 0 && length(module.artifacts_bucket) == 0
    )
    error_message = "Nothing should be created when everything is brought."
  }

  assert {
    condition = (
      output.autoheal_values.global.infra.database.host == "acme-pg.cluster-abc.us-west-2.rds.amazonaws.com" &&
      output.autoheal_values.global.infra.database.adminUser == "pgadmin" &&
      output.autoheal_values.global.infra.redis.host == "master.acme-redis.abc.usw2.cache.amazonaws.com" &&
      output.autoheal_values.global.infra.objectStore.bucket == "acme-attachments" &&
      output.autoheal_values.global.infra.objectStore.artifactsBucket == "acme-artifacts" &&
      output.autoheal_values.global.imageRegistry == "123456789012.dkr.ecr.us-west-2.amazonaws.com/autoheal"
    )
    error_message = "Facts should come from the brought resources."
  }

  assert {
    condition = (
      output.cluster.name == "acme-eks" &&
      output.cluster.endpoint == "https://ABCDEF.gr7.us-west-2.eks.amazonaws.com" &&
      output.network.vpc_id == "vpc-0123456789abcdef0" &&
      output.network.vpc_cidr_block == "10.20.0.0/16" &&
      tolist(output.network.runner_subnet_ids) == tolist(["subnet-0a", "subnet-0b", "subnet-0c"]) &&
      tolist(output.network.data_subnet_ids) == tolist(["subnet-0a", "subnet-0b", "subnet-0c"])
    )
    error_message = "Cluster and network should be the brought ones, with runner and data subnets falling back to private."
  }

  assert {
    condition     = local.runner_ecr_host == "123456789012.dkr.ecr.us-west-2.amazonaws.com"
    error_message = "A brought ECR registry should turn on the runner's ECR helper."
  }

  assert {
    condition = (
      length(terraform_data.eks_guard) == 1 && length(terraform_data.postgres_guard) == 1 &&
      length(terraform_data.redis_guard) == 1 && length(terraform_data.bucket_guard) == 2 &&
      length(terraform_data.kms_guard) == 1
    )
    error_message = "Every brought resource should be checked."
  }

  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 6 &&
      strcontains(output.required_cluster_owner_actions[0], "acme-eks for the deployer (arn:aws:iam::123456789012:role/deployer)") &&
      strcontains(output.required_cluster_owner_actions[1], "eks:CreatePodIdentityAssociation") &&
      strcontains(output.required_cluster_owner_actions[1], "sg-0cluster0000000000") &&
      strcontains(output.required_cluster_owner_actions[1], "TCP 7233, 8083, 8443, 8090") &&
      strcontains(output.required_cluster_owner_actions[2], "eks-pod-identity-agent and aws-secrets-store-csi-driver-provider") &&
      strcontains(output.required_cluster_owner_actions[3], "global.infra.targetGroups") &&
      strcontains(output.required_cluster_owner_actions[4], "private API endpoint of acme-eks") &&
      strcontains(output.required_cluster_owner_actions[5], "123456789012.dkr.ecr.us-west-2.amazonaws.com/autoheal")
    )
    error_message = "required_cluster_owner_actions should list the access entry, IAM, add-ons, controller, private endpoint and registry."
  }
}

run "brought_cluster_public_endpoint" {
  command = plan

  variables {
    edge_mode                            = "istio"
    create_load_balancer_controller_role = true
    create_pod_identity_associations     = false
    existing_registry_url                = ""
    create_registry                      = true
  }

  override_data {
    target = data.aws_eks_cluster.existing
    values = {
      endpoint              = "https://ABCDEF.gr7.us-west-2.eks.amazonaws.com"
      status                = "ACTIVE"
      certificate_authority = [{ data = "Q0E=" }]
      vpc_config = [{
        vpc_id                    = "vpc-0123456789abcdef0"
        cluster_security_group_id = "sg-0cluster0000000000"
        endpoint_public_access    = true
      }]
    }
  }

  assert {
    condition = (
      length(output.required_cluster_owner_actions) == 5 &&
      !strcontains(output.required_cluster_owner_actions[1], "eks:CreatePodIdentityAssociation") &&
      endswith(output.required_cluster_owner_actions[1], "TCP 7233, 8083") &&
      strcontains(output.required_cluster_owner_actions[3], "aws_load_balancer_controller.enabled = true") &&
      strcontains(output.required_cluster_owner_actions[4], "acme-prod-autoheal-ecr-pull-through")
    )
    error_message = "A public endpoint, our controller role and our registry should change the owner's list."
  }
}

run "rds_instance" {
  command = plan

  variables {
    existing_postgres_arn = "arn:aws:rds:us-west-2:123456789012:db:acme-pg"
  }

  assert {
    condition     = output.autoheal_values.global.infra.database.host == "acme-pg.abc.us-west-2.rds.amazonaws.com"
    error_message = "A brought RDS instance should give its address."
  }
}

run "hybrid_network_only" {
  command = plan

  variables {
    existing_eks_cluster_arn        = ""
    existing_postgres_arn           = ""
    existing_redis_arn              = ""
    existing_attachments_bucket_arn = ""
    existing_artifacts_bucket_arn   = ""
    existing_kms_key_arn            = ""
    existing_registry_url           = ""
    postgres_admin_password         = ""
    redis_auth_token                = ""
    existing_network = {
      vpc_id             = "vpc-0123456789abcdef0"
      private_subnet_ids = ["subnet-0a", "subnet-0b", "subnet-0c"]
      data_subnet_ids    = ["subnet-0d", "subnet-0e", "subnet-0f"]
      public_subnet_ids  = ["subnet-01", "subnet-02", "subnet-03"]
    }
  }

  assert {
    condition = (
      length(module.vpc) == 0 && length(module.eks) == 1 && length(module.postgres) == 1 &&
      length(module.redis) == 1 && length(module.kms) == 5 &&
      tolist(output.network.data_subnet_ids) == tolist(["subnet-0d", "subnet-0e", "subnet-0f"]) &&
      tolist(output.network.runner_subnet_ids) == tolist(["subnet-0a", "subnet-0b", "subnet-0c"])
    )
    error_message = "A brought network should create everything else in it."
  }
}

run "postgres_too_old" {
  command = plan

  override_data {
    target = data.aws_rds_cluster.existing
    values = { engine = "aurora-postgresql", engine_version = "14.9", port = 5432 }
  }

  expect_failures = [terraform_data.postgres_guard]
}

run "postgres_wrong_engine" {
  command = plan

  override_data {
    target = data.aws_rds_cluster.existing
    values = { engine = "aurora-mysql", engine_version = "8.0.mysql_aurora.3.05.2", port = 3306 }
  }

  expect_failures = [terraform_data.postgres_guard]
}

run "cluster_in_other_vpc" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.existing
    values = {
      status                = "ACTIVE"
      certificate_authority = [{ data = "Q0E=" }]
      vpc_config            = [{ vpc_id = "vpc-0ffffffffffffffff", cluster_security_group_id = "sg-0cluster0000000000" }]
    }
  }

  expect_failures = [terraform_data.eks_guard]
}

run "redis_cluster_mode" {
  command = plan

  override_data {
    target = data.aws_elasticache_replication_group.existing
    values = { primary_endpoint_address = "", port = 6379, auth_token_enabled = true }
  }

  expect_failures = [terraform_data.redis_guard]
}

run "redis_token_missing" {
  command = plan

  variables {
    redis_auth_token = ""
  }

  expect_failures = [terraform_data.redis_guard]
}

run "bucket_in_other_region" {
  command = plan

  override_data {
    target = data.aws_s3_bucket.existing
    values = { bucket_region = "eu-west-1" }
  }

  expect_failures = [terraform_data.bucket_guard]
}

run "kms_key_asymmetric" {
  command = plan

  override_data {
    target = data.aws_kms_key.existing
    values = { enabled = true, key_spec = "RSA_2048", key_usage = "SIGN_VERIFY" }
  }

  expect_failures = [terraform_data.kms_guard]
}

run "postgres_password_missing" {
  command = plan

  variables {
    postgres_admin_password = ""
  }

  expect_failures = [terraform_data.validate_inputs]
}
