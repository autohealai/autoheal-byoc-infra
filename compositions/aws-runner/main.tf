# The runner step, optional and applied after the app. Runner instances run
# runner-go on an EC2 Auto Scaling group (modules/aws/runner-asg) and poll
# Temporal at temporal_address.
#
# The runner connects the way Autoheal's hosted runners do: to the internal
# runner load balancer of compositions/aws (runner_lb_enabled, its
# runner_load_balancer output), Temporal on 7233 and sandbox tool results on
# 8083, in plain gRPC and HTTP with no TLS and no key. The load balancer's
# security group decides who may connect, so the addresses must be private:
# the checks below refuse a public address, a load balancer that is not
# internal, and any other name that could resolve to a public address.
# Sandboxes, which run untrusted code, are kept off those addresses by a
# firewall on each instance.
#
# The runner only dials out. This composition never reads the cluster: the
# addresses are inputs (it only looks up a load balancer named in them), and the network owner opens the path listed in
# required_network_owner_actions. Until then the runner keeps retrying. Turn
# sandboxes on in the chart (global.sandbox.enabled) only after the runner
# shows up as a poller.
#
# Where a central team owns IAM or security groups, existing_instance_profile_arn
# and existing_security_group_id replace ours, and required_role_policies lists
# what the brought role needs.
#
# The image is <runner_image>:chart-<chart_version>, the tag published with each
# chart release. The instances retry the pull until it succeeds, so the image
# may be pushed to a new registry after the apply.

data "aws_subnet" "this" {
  for_each = toset(var.subnet_ids)
  id       = each.value
}

# The load balancers named in temporal_address and tool_response_url, to check
# they are internal. One in another account or region is not found: use its
# private address or a name under private_dns_domains instead.
data "aws_lb" "address" {
  for_each = toset([for k, n in local.lb_names : n if n != null && !local.private_by_form[k]])
  name     = each.value
}

locals {
  # null-label id, e.g. acme-prod-autoheal. Resources add a -runner suffix.
  id = lower(join("-", compact([var.namespace, var.environment, var.name])))

  # --- Network --------------------------------------------------------------

  vpc_ids      = distinct([for s in data.aws_subnet.this : s.vpc_id])
  subnet_cidrs = [for id in var.subnet_ids : data.aws_subnet.this[id].cidr_block]

  # --- Temporal and tool results --------------------------------------------

  temporal_host = split(":", var.temporal_address)[0]
  temporal_port = split(":", var.temporal_address)[1]

  # Scheme, host and port of tool_response_url, for the network rule. An empty
  # tool_response_url sends tool results through Temporal.
  tool_response      = var.tool_response_url == "" ? null : regex("^(https?)://([^/:]+)(?::([0-9]+))?", var.tool_response_url)
  tool_response_host = local.tool_response == null ? "" : local.tool_response[1]
  tool_response_port = local.tool_response == null ? "" : coalesce(local.tool_response[2], local.tool_response[0] == "https" ? "443" : "80")

  hosts = { temporal = local.temporal_host, tool_response = local.tool_response_host }

  # Whether a host is private by its form: an IPv4 address in the private
  # ranges, or a name under private_dns_domains.
  private_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"]
  private_by_form = { for k, h in local.hosts : k => h != "" && (
    can(cidrhost("${h}/32", 0)) ? anytrue([
      for r in local.private_ranges : cidrhost("${h}/${split("/", r)[1]}", 0) == split("/", r)[0]
    ]) : anytrue([for d in var.private_dns_domains : endswith(lower(h), ".${d}")])
  ) }

  # A load balancer's DNS name carries its name: <name>-<id>.elb.<region>.amazonaws.com
  # for a network load balancer, [internal-]<name>-<id>.<region>.elb.amazonaws.com
  # for an application one. An internal network load balancer's name looks
  # like an internet-facing one's, so the load balancer is looked up below.
  lb_names = { for k, h in local.hosts : k => try(regex(
    "^(?:internal-)?([a-z0-9-]+)-[0-9a-f]+\\.(?:elb\\.[a-z0-9-]+|[a-z0-9-]+\\.elb)\\.amazonaws\\.com(?:\\.cn)?$", lower(h)
  )[0], null) }

  private_hosts = { for k, h in local.hosts : k => local.private_by_form[k] || (
    local.lb_names[k] != null && try(
      data.aws_lb.address[local.lb_names[k]].internal && lower(data.aws_lb.address[local.lb_names[k]].dns_name) == lower(h),
      false
    )
  ) }

  # --- Image ----------------------------------------------------------------

  runner_image = "${var.runner_image}:${var.runner_image_tag != "" ? var.runner_image_tag : "chart-${var.chart_version}"}"
}

# Plan-time checks with plain messages. (Input validation blocks cannot refer to
# other variables on Terraform 1.7, so checks that combine inputs live here.)
resource "terraform_data" "validate_inputs" {
  lifecycle {
    precondition {
      condition     = length(local.vpc_ids) == 1
      error_message = "subnet_ids are in more than one VPC (${join(", ", local.vpc_ids)}). An Auto Scaling group and its security group live in one VPC: pass subnets of one VPC, such as the network.private_subnet_ids output of compositions/aws."
    }
    precondition {
      condition     = local.private_hosts.temporal
      error_message = "temporal_address must be private: Temporal takes no TLS and no key there, and the traffic carries git tokens and command output. ${local.temporal_host} is not a private IPv4 address (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 or 100.64.0.0/10), an internal load balancer of this account and region, or a name under private_dns_domains. Use the temporal_address of the runner_load_balancer output of compositions/aws."
    }
    precondition {
      condition     = local.tool_response == null ? true : (local.tool_response[0] == "https" || local.private_hosts.tool_response)
      error_message = "An http:// tool_response_url must be private like temporal_address: tool results carry command output. ${local.tool_response_host} is not a private IPv4 address, an internal load balancer of this account and region, or a name under private_dns_domains. Use the tool_response_url of the runner_load_balancer output of compositions/aws, or leave it empty to send tool results through Temporal."
    }
    precondition {
      condition     = var.tool_response_token_secret == null || startswith(var.tool_response_url, "https://")
      error_message = "tool_response_token_secret is set but tool_response_url is not an https:// URL, so the key would cross the network in plain text, or go nowhere. Set tool_response_url to https://<app host>/api/v1/internal/sandbox-tool-responses, or leave tool_response_token_secret null for the runner load balancer on 8083."
    }
    precondition {
      condition     = var.ecr_repository_prefix == "" || var.ecr_registry_host != ""
      error_message = "ecr_repository_prefix limits the pull policy on ecr_registry_host, which is empty. Set ecr_registry_host, or leave ecr_repository_prefix empty."
    }
  }
}

module "runner" {
  source = "../../modules/aws/runner-asg"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["runner"]
  tags        = var.tags

  vpc_id                        = local.vpc_ids[0]
  subnet_ids                    = var.subnet_ids
  existing_security_group_id    = var.existing_security_group_id
  additional_security_group_ids = var.additional_security_group_ids
  egress_cidr_blocks            = var.egress_cidr_blocks
  ssh_ingress_cidr_blocks       = var.ssh_ingress_cidr_blocks
  http_proxy                    = var.http_proxy
  no_proxy                      = var.no_proxy
  trusted_ca_certificates       = var.trusted_ca_certificates
  custom_ca_certificate         = var.custom_ca_certificate

  instance_type                           = var.instance_type
  architecture                            = var.architecture
  ami_id                                  = var.ami_id
  ami_name_filter                         = var.ami_name_filter
  ami_owners                              = var.ami_owners
  instance_count                          = var.instance_count
  instance_refresh_min_healthy_percentage = var.instance_refresh_min_healthy_percentage
  instance_refresh_max_healthy_percentage = var.instance_refresh_max_healthy_percentage
  root_volume_size_gb                     = var.root_volume_size_gb
  root_volume_kms_key_arn                 = var.root_volume_kms_key_arn
  key_name                                = var.key_name
  ssm_enabled                             = var.ssm_enabled

  existing_instance_profile_arn = var.existing_instance_profile_arn
  additional_iam_policy_arns    = var.additional_iam_policy_arns
  permissions_boundary_arn      = var.iam_permissions_boundary_arn

  temporal_host                = var.temporal_address
  tool_response_callback_url   = var.tool_response_url
  sandbox_blocked_destinations = var.sandbox_blocked_destinations
  runner_image                 = local.runner_image
  sandbox_image                = var.sandbox_image
  runner_name                  = "${local.id}-runner"
  max_concurrent_activities    = var.max_concurrent_activities
  ecr_registry_host            = var.ecr_registry_host
  ecr_repository_prefix        = var.ecr_repository_prefix

  tool_response_token_secret_arn  = try(var.tool_response_token_secret.arn, "")
  tool_response_token_kms_key_arn = try(var.tool_response_token_secret.kms_key_arn, "")
}
