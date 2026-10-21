# Case 1: we create everything. Runs a real plan against mocked providers, so no
# account is touched. Covers the hand-off values, the names, each edge mode, the
# DNS records and their listing, and the optional blocks.
#
# Under a mocked provider, data sources return the defaults below and created
# resources have unknown computed attributes at plan time, so the assertions use
# values the plan knows: inputs, names and counts.

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

run "everything_created" {
  command = plan

  assert {
    condition = (
      output.autoheal_values.global.infra.version == "2.1.0" &&
      output.autoheal_values.global.infra.cloud == "aws" &&
      output.autoheal_values.global.infra.region == "us-west-2"
    )
    error_message = "global.infra header is wrong."
  }

  assert {
    condition = output.autoheal_values.global.infra.hosts == {
      app     = "autoheal.acme.example"
      auth    = "auth.autoheal.acme.example"
      authApp = "auth-app.autoheal.acme.example"
    }
    error_message = "Hostnames are wrong."
  }

  assert {
    condition = (
      output.autoheal_values.global.infra.secretsManager.prefix == "acme-prod-autoheal/" &&
      output.autoheal_values.global.infra.runtimeSecrets == { kind = "awssecretsmanager", region = "us-west-2", prefix = "acme-prod-autoheal-runtime" }
    )
    error_message = "Secrets Manager prefixes are wrong."
  }

  assert {
    condition = (
      output.autoheal_values.global.infra.objectStore.kind == "s3" &&
      output.autoheal_values.global.infra.objectStore.bucket == "acme-prod-autoheal-attachments" &&
      output.autoheal_values.global.infra.objectStore.artifactsBucket == "acme-prod-autoheal-artifacts" &&
      output.autoheal_values.global.infra.objectStore.tenantBucketPrefix == "acme-prod-autoheal-"
    )
    error_message = "objectStore is wrong."
  }

  assert {
    condition = (
      length(module.tenant_bucket) == 1 &&
      local.tenant_bucket == "acme-prod-autoheal-00000000-0000-0000-0000-000000000001"
    )
    error_message = "The tenant bucket should be created with the default tenant ID."
  }

  assert {
    condition = (
      output.autoheal_values.global.infra.database.port == 5432 &&
      output.autoheal_values.global.infra.database.adminPasswordVaultEntry == "postgres-admin-password" &&
      contains(keys(output.autoheal_values.global.infra), "redis")
    )
    error_message = "database or redis facts are wrong."
  }

  assert {
    condition     = toset(keys(output.autoheal_values.global.infra.targetGroups)) == toset(["temporal", "toolResponse", "edgeHttps", "edgeHttp"])
    error_message = "loadbalancer mode needs the runner and edge target groups."
  }

  assert {
    condition = (
      output.autoheal_values.global.addons.install == false &&
      output.autoheal_values.global.secrets.mode == "keyvault-csi" &&
      output.autoheal_values.global.edge == { mode = "loadbalancer" } &&
      !contains(keys(output.autoheal_values.global), "imageRegistry") &&
      !contains(keys(output.autoheal_values.global), "llm")
    )
    error_message = "Suggestions are wrong."
  }

  assert {
    condition = (
      length(module.vpc) == 1 && length(module.eks) == 1 && length(module.postgres) == 1 &&
      length(module.redis) == 1 && length(module.kms) == 5 && length(module.ecr) == 0 &&
      length(module.edge_nlb) == 1 && length(module.lb_controller_identity) == 1
    )
    error_message = "Case 1 should create every block except the registry."
  }

  assert {
    condition = (
      local.dns_records.app.type == "A" &&
      length(local.dns_records.app.records) == 0 &&
      length(module.dns) == 1 &&
      local.dns_records.auth.name == "auth.autoheal.acme.example" &&
      length(output.required_dns_records) == 0
    )
    error_message = "loadbalancer mode should create alias A records and list none."
  }

  assert {
    condition = (
      length(output.required_role_assignments) == 0 &&
      length(local.role_bindings) == 5
    )
    error_message = "Associations are created, so none are listed."
  }

  assert {
    condition = (
      local.runner_image == "public.ecr.aws/e4h3h0d9/app/runner-go:chart-2.1.0" &&
      local.runner_ecr_host == ""
    )
    error_message = "Without a registry the runner pulls from the public registry."
  }

  assert {
    condition = toset(local.secret_entry_names) == toset([
      "postgres-admin-password", "api-server-db-password", "agents-db-password", "temporal-db-password",
      "zitadel-db-password", "api-server-database-url", "api-server-jwt-secret", "zitadel-master-key",
      "auth-app-session-secret", "first-admin-password", "oauth-encryption-key", "oauth-state-signing-key",
      "tool-response-server-secret", "redis-access-key", "api-server-redis-url",
    ])
    error_message = "Secret entries are wrong."
  }

  assert {
    condition     = output.cluster.cloud == "aws" && output.cluster.name == "acme-prod-autoheal" && output.cluster.region == "us-west-2"
    error_message = "cluster output is wrong."
  }

  assert {
    condition = (
      local.created_subnets.private == ["10.60.0.0/19", "10.60.32.0/19", "10.60.64.0/19"] &&
      local.created_subnets.runner == ["10.60.128.0/24", "10.60.129.0/24", "10.60.130.0/24"] &&
      local.created_subnets.data == ["10.60.136.0/24", "10.60.137.0/24", "10.60.138.0/24"] &&
      local.created_subnets.public == ["10.60.144.0/24", "10.60.145.0/24", "10.60.146.0/24"]
    )
    error_message = "Subnet layout is wrong."
  }

  assert {
    condition = (
      output.autoheal_values.temporal.server.config.persistence.default.sql.host == output.autoheal_values.global.infra.database.host &&
      output.autoheal_values.zitadel.zitadel.configmapConfig.ExternalDomain == "auth.autoheal.acme.example"
    )
    error_message = "Temporal and Zitadel copies are wrong."
  }
}

run "registry_created" {
  command = plan

  variables {
    create_registry = true
  }

  assert {
    condition     = output.autoheal_values.global.imageRegistry == "123456789012.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9"
    error_message = "imageRegistry should point at the pull-through cache."
  }

  assert {
    condition = (
      output.autoheal_values.temporal.server.image.repository == "123456789012.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9/external/temporal-server" &&
      output.autoheal_values.zitadel.imageRegistry == "123456789012.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9"
    )
    error_message = "Temporal and Zitadel images should come from the registry."
  }

  assert {
    condition = (
      local.runner_image == "123456789012.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9/app/runner-go:chart-2.1.0" &&
      local.runner_ecr_host == "123456789012.dkr.ecr.us-west-2.amazonaws.com" &&
      length(module.ecr) == 1 && length(aws_iam_policy.ecr_pull_through) == 1
    )
    error_message = "The runner should pull from the registry with the ECR helper."
  }
}

run "gateway_with_dns_name" {
  command = plan

  variables {
    edge_mode    = "gateway-api"
    edge_address = "gw.acme.example"
  }

  assert {
    condition = (
      length(module.edge_nlb) == 0 &&
      toset(keys(output.autoheal_values.global.infra.targetGroups)) == toset(["temporal", "toolResponse"]) &&
      local.dns_records.app.type == "CNAME" && tolist(local.dns_records.app.records) == tolist(["gw.acme.example"]) &&
      local.dns_records.app.alias == null &&
      length(module.dns) == 1 && length(output.required_dns_records) == 0
    )
    error_message = "gateway-api with a DNS name should create CNAME records and no edge load balancer."
  }
}

run "istio_without_address" {
  command = plan

  variables {
    edge_mode = "istio"
  }

  assert {
    condition = (
      length(module.dns) == 0 &&
      length(output.required_dns_records) == 3 &&
      output.required_dns_records[0].type == "A or CNAME"
    )
    error_message = "With no edge_address the records are listed, not created."
  }
}

run "ingress_with_ip" {
  command = plan

  variables {
    edge_mode    = "ingress"
    edge_address = "10.60.0.50"
  }

  assert {
    condition     = local.dns_records.auth.type == "A" && tolist(local.dns_records.auth.records) == tolist(["10.60.0.50"])
    error_message = "An IPv4 edge_address should give A records."
  }
}

run "edge_none" {
  command = plan

  variables {
    edge_mode = "none"
  }

  assert {
    condition     = length(module.dns) == 0 && length(output.required_dns_records) == 0 && length(module.edge_nlb) == 0
    error_message = "edge_mode none should have no records and no edge load balancer."
  }
}

run "no_dns_zone" {
  command = plan

  variables {
    existing_dns_zone_id = ""
    create_dns_records   = false
  }

  assert {
    condition     = length(module.dns) == 0 && length(output.required_dns_records) == 3 && output.required_dns_records[0].type == "CNAME"
    error_message = "Without a zone the records are listed as CNAMEs to the edge load balancer."
  }
}

run "internet_facing_edge" {
  command = plan

  variables {
    edge_exposure            = "internet-facing"
    edge_allowed_cidr_blocks = ["0.0.0.0/0"]
  }

  assert {
    condition     = length(module.edge_nlb) == 1
    error_message = "internet-facing edge should plan."
  }
}

run "associations_by_administrator" {
  command = plan

  variables {
    create_pod_identity_associations = false
  }

  assert {
    # The role ARNs are unknown at plan time, so only the count is checked.
    condition = (
      length(output.required_role_assignments) == 5 &&
      toset([for b in local.role_bindings : "${b.ns}/${b.sa}"]) == toset([
        "autoheal/autoheal-hooks", "autoheal/api-server-go", "autoheal/agents-py-http",
        "autoheal/agents-py-worker", "kube-system/aws-load-balancer-controller",
      ])
    )
    error_message = "Each association should be listed as a command."
  }
}

run "no_redis" {
  command = plan

  variables {
    redis_enabled = false
  }

  assert {
    condition = (
      length(module.redis) == 0 &&
      !contains(keys(output.autoheal_values.global.infra), "redis") &&
      !contains(local.secret_entry_names, "redis-access-key")
    )
    error_message = "redis_enabled = false should leave out Redis."
  }
}

run "optional_entries" {
  command = plan

  variables {
    llm_gateway_extra_headers = "{\"x-portkey-config\":\"pc-acme\"}"
    edge_ca_certificate       = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
    sso_client_secret         = "s"
    github_app_private_key    = "-----BEGIN RSA PRIVATE KEY-----\nMIIB\n-----END RSA PRIVATE KEY-----"
  }

  assert {
    condition = (
      output.autoheal_values.global.llm.gateway == { extraHeadersVaultEntry = "gateway-extra-headers", apiKeyVaultEntry = "" } &&
      output.autoheal_values.global.edge.tls.caVaultEntry == "edge-ca-certificate" &&
      contains(local.secret_entry_names, "gateway-extra-headers") &&
      contains(local.secret_entry_names, "sso-client-secret") &&
      contains(local.secret_entry_names, "github-app-private-key") &&
      !contains(local.secret_entry_names, "gateway-api-key")
    )
    error_message = "Optional entries and their suggestions are wrong."
  }
}

run "private_vpc" {
  command = plan

  variables {
    nat_gateway_mode          = "none"
    private_endpoints_enabled = true
    create_registry           = true
    private_cluster_enabled   = true
  }

  assert {
    condition     = length(module.vpc) == 1
    error_message = "A VPC with no NAT gateway, endpoints and a registry should plan."
  }
}

# OpenTofu overrides every instance of a data source, so each run looks up one
# permission set: an override target with an instance key fails there.
run "cluster_access" {
  command = plan

  variables {
    cluster_admin_principal_arns      = ["arn:aws:iam::123456789012:role/break-glass"]
    cluster_viewer_principal_arns     = ["arn:aws:iam::123456789012:role/audit"]
    cluster_admin_sso_permission_sets = ["AutohealAdmin"]
  }

  override_data {
    target = data.aws_iam_roles.sso
    values = { arns = ["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_AutohealAdmin_0123456789abcdef"] }
  }

  assert {
    condition = (
      data.aws_iam_roles.sso["sso-admin-AutohealAdmin"].name_regex == "^AWSReservedSSO_AutohealAdmin_[0-9a-f]+$" &&
      data.aws_iam_roles.sso["sso-admin-AutohealAdmin"].path_prefix == "/aws-reserved/sso.amazonaws.com/"
    )
    error_message = "Permission sets should be looked up by role name under the Identity Center path."
  }

  assert {
    condition = local.cluster_access_entries == {
      "arn:aws:iam::123456789012:role/break-glass" = {
        principal_arn = "arn:aws:iam::123456789012:role/break-glass"
        policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      }
      "arn:aws:iam::123456789012:role/audit" = {
        principal_arn = "arn:aws:iam::123456789012:role/audit"
        policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
      }
      "sso-admin-AutohealAdmin" = {
        principal_arn = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_AutohealAdmin_0123456789abcdef"
        policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      }
    }
    error_message = "Access entries should give admins the cluster admin policy and viewers the view policy."
  }

  assert {
    condition     = length(output.required_cluster_owner_actions) == 0
    error_message = "A cluster we create needs nothing from an owner."
  }
}

run "cluster_viewer_permission_set" {
  command = plan

  variables {
    cluster_viewer_sso_permission_sets = ["Ops.View+1"]
  }

  override_data {
    target = data.aws_iam_roles.sso
    values = { arns = ["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Ops.View+1_fedcba9876543210"] }
  }

  assert {
    condition     = data.aws_iam_roles.sso["sso-viewer-Ops.View+1"].name_regex == "^AWSReservedSSO_Ops\\.View\\+1_[0-9a-f]+$"
    error_message = "Regex operators in a permission set name should be escaped."
  }

  assert {
    condition = local.cluster_access_entries["sso-viewer-Ops.View+1"] == {
      principal_arn = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Ops.View+1_fedcba9876543210"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    }
    error_message = "A viewer permission set should get the view policy."
  }
}
