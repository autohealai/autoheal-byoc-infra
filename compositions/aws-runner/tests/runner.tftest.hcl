# Plans of compositions/aws-runner against mocked providers: the identity and
# security group we create or bring, the AMI, the image and registry, the path
# to Temporal (the runner load balancer, a private address or a private name),
# the network owner's lines, and the input checks. Nothing here reaches AWS.
# The runner instances' cloud-init is tested in cloudinit.tftest.hcl.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com", reverse_dns_prefix = "com.amazonaws" }
  }
  # The runner load balancer of compositions/aws, internal.
  mock_data "aws_lb" {
    defaults = { internal = true, dns_name = "acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com" }
  }
  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-0123456789abcdef0", cidr_block = "10.60.1.0/24" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0123456789abcdef0", value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_ami" {
    defaults = { id = "ami-0123456789abcdef0", architecture = "x86_64", root_device_name = "/dev/xvda" }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["x86_64"] }
  }

  # Well-formed IDs where one resource takes another's: OpenTofu fills computed
  # strings at random, and the provider parses these.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/acme-prod-autoheal-runner-role" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::123456789012:instance-profile/acme-prod-autoheal-runner-profile" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0123456789abcdef0" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0" }
  }
}

variables {
  account_id        = "123456789012"
  region            = "us-west-2"
  namespace         = "acme"
  environment       = "prod"
  chart_version     = "1.0.0"
  subnet_ids        = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  temporal_address  = "acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:7233"
  tool_response_url = "http://acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:8083/api/v1/internal/sandbox-tool-responses"
}

# The defaults: our role and security group, the latest Amazon Linux 2023,
# public images, SSM Session Manager, and the runner load balancer of
# compositions/aws for Temporal and tool results, as on Autoheal's hosted
# runners.
run "runner_load_balancer" {
  command = plan

  assert {
    condition     = output.autoscaling_group_name == "acme-prod-autoheal-runner"
    error_message = "The Auto Scaling group is named <id>-runner."
  }

  assert {
    condition     = output.ami_id == "ami-0123456789abcdef0"
    error_message = "Without ami_id or ami_name_filter the AMI is the latest Amazon Linux 2023."
  }

  assert {
    condition     = toset(keys(data.aws_lb.address)) == toset(["acme-prod-autoheal-runner"])
    error_message = "The load balancer named in both addresses is looked up once, by its name."
  }

  assert {
    condition     = length(output.required_role_policies.inline_policies) == 0
    error_message = "With public images and no key the role needs no inline policy."
  }

  assert {
    condition     = output.required_role_policies.managed_policy_arns == tomap({ ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" })
    error_message = "ssm_enabled attaches AmazonSSMManagedInstanceCore."
  }

  assert {
    condition     = output.subnet_cidrs == ["10.60.1.0/24", "10.60.1.0/24"]
    error_message = "subnet_cidrs lists the ranges of subnet_ids in order."
  }

  assert {
    condition = output.required_network_owner_actions == [
      "The runner subnets (10.60.1.0/24, 10.60.1.0/24) need a route to acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com and must be let in there on TCP 7233 and 8083 (Temporal and sandbox tool results). The runner load balancer of compositions/aws lets in its VPC by default; from another network, or to let in only the runner, set its runner_lb_allowed_cidr_blocks or runner_lb_allowed_security_group_ids.",
      "The runner subnets (10.60.1.0/24, 10.60.1.0/24) need outbound access to the image registry (public.ecr.aws), SSM Session Manager (the ssm, ssmmessages and ec2messages endpoints of us-west-2), the git hosts and the endpoints the tools call. The instances get no public address.",
    ]
    error_message = "The network owner opens 7233 and 8083 to the runner load balancer and the outbound targets."
  }
}

# A central team owns IAM and the security group; no SSM, SSH with a key pair,
# a company AMI and a proxy.
run "brought_identity_group_and_ami" {
  command = plan

  variables {
    existing_instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/acme-runner"
    existing_security_group_id    = "sg-0fedcba9876543210"
    ssm_enabled                   = false
    key_name                      = "acme-runner"
    ami_name_filter               = "*golden-amzn-linux-2023-v*"
    ami_owners                    = ["210987654321"]
    http_proxy                    = "http://proxy.acme.example:8080"
    tags                          = { CostCenter = "1234" }
  }

  override_data {
    target = module.runner.data.aws_ami.by_name
    values = { id = "ami-0fedcba9876543210" }
  }

  assert {
    condition     = output.ami_id == "ami-0fedcba9876543210"
    error_message = "ami_name_filter picks the newest matching AMI."
  }

  assert {
    condition     = output.iam_role_arn == "" && output.instance_profile_arn == var.existing_instance_profile_arn
    error_message = "With existing_instance_profile_arn we create no role."
  }

  assert {
    condition     = output.security_group_id == var.existing_security_group_id
    error_message = "With existing_security_group_id we create no security group."
  }

  assert {
    condition     = length(output.required_role_policies.managed_policy_arns) == 0 && length(output.required_role_policies.inline_policies) == 0
    error_message = "Without ssm_enabled, a registry or a key the brought role needs no policy."
  }

  assert {
    condition     = strcontains(output.required_role_policies.trust_policy, "ec2.amazonaws.com")
    error_message = "The brought role must trust EC2."
  }

  assert {
    condition     = output.required_network_owner_actions[1] == "The runner subnets (10.60.1.0/24, 10.60.1.0/24) need outbound access through http://proxy.acme.example:8080 to the image registry (public.ecr.aws), the git hosts and the endpoints the tools call. The instances get no public address."
    error_message = "With http_proxy the outbound line names the proxy, and without ssm_enabled it leaves out SSM."
  }

  assert {
    condition     = output.required_network_owner_actions[2] == "The security group sg-0fedcba9876543210 is brought, so we add no rule to it: let it out to acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com on TCP 7233 and 8083 and to the proxy, and to the targets above on TCP 443. For SSH, let your jump hosts in on TCP 22."
    error_message = "A brought security group gets a line with the rules it needs."
  }
}

# Images from the ECR pull-through cache of compositions/aws.
run "private_ecr" {
  command = plan

  variables {
    runner_image          = "123456789012.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9/app/runner-go"
    runner_image_tag      = "chart-1.0.0-hotfix.1"
    ecr_registry_host     = "123456789012.dkr.ecr.us-west-2.amazonaws.com"
    ecr_repository_prefix = "acme-prod-autoheal"
  }

  assert {
    condition     = toset(keys(output.required_role_policies.inline_policies)) == toset(["ecr-pull"])
    error_message = "With a private registry the role gets ecr-pull alone."
  }

  assert {
    condition     = jsondecode(output.required_role_policies.inline_policies["ecr-pull"]).Statement[1].Resource == "arn:aws:ecr:us-west-2:123456789012:repository/acme-prod-autoheal/*"
    error_message = "The ecr-pull policy is limited to ecr_repository_prefix."
  }

  assert {
    condition     = contains(jsondecode(output.required_role_policies.inline_policies["ecr-pull"]).Statement[1].Action, "ecr:BatchImportUpstreamImage")
    error_message = "A pull-through cache needs ecr:BatchImportUpstreamImage on the first pull."
  }

  assert {
    condition     = strcontains(output.required_network_owner_actions[1], "the image registry (123456789012.dkr.ecr.us-west-2.amazonaws.com)")
    error_message = "The outbound line names the private registry."
  }
}

# Private IPv4 addresses need no lookup. Tool results on another host get a
# line of their own.
run "private_addresses" {
  command = plan

  variables {
    temporal_address  = "10.60.15.253:7233"
    tool_response_url = "http://10.60.20.5:8083/api/v1/internal/sandbox-tool-responses"
  }

  assert {
    condition     = length(data.aws_lb.address) == 0
    error_message = "A private IPv4 address is not looked up."
  }

  assert {
    condition = slice(output.required_network_owner_actions, 0, 2) == [
      "The runner subnets (10.60.1.0/24, 10.60.1.0/24) need a route to 10.60.15.253 and must be let in there on TCP 7233 (Temporal). The runner load balancer of compositions/aws lets in its VPC by default; from another network, or to let in only the runner, set its runner_lb_allowed_cidr_blocks or runner_lb_allowed_security_group_ids.",
      "The runner subnets (10.60.1.0/24, 10.60.1.0/24) need a route to 10.60.20.5 and must be let in there on TCP 8083 (sandbox tool results).",
    ]
    error_message = "Temporal and tool results on two hosts get a line each."
  }
}

# A name in a private zone, with tool results through Temporal.
run "private_dns_domain" {
  command = plan

  variables {
    temporal_address    = "runner.acme.internal:7233"
    tool_response_url   = ""
    private_dns_domains = ["acme.internal"]
  }

  assert {
    condition     = length(data.aws_lb.address) == 0 && startswith(output.required_network_owner_actions[0], "The runner subnets (10.60.1.0/24, 10.60.1.0/24) need a route to runner.acme.internal and must be let in there on TCP 7233 (Temporal).")
    error_message = "A name under private_dns_domains is private and not looked up."
  }
}

# --- Input checks -----------------------------------------------------------

run "temporal_address_needs_a_port" {
  command = plan

  variables {
    temporal_address = "runner.acme.internal"
  }

  expect_failures = [var.temporal_address]
}

run "temporal_address_port_in_range" {
  command = plan

  variables {
    temporal_address = "runner.acme.internal:99999"
  }

  expect_failures = [var.temporal_address]
}

run "private_dns_domain_without_leading_dot" {
  command = plan

  variables {
    private_dns_domains = [".acme.internal"]
  }

  expect_failures = [var.private_dns_domains]
}

run "blocked_destination_cidr_from_its_first_address" {
  command = plan

  variables {
    sandbox_blocked_destinations = ["10.60.1.0/16"]
  }

  expect_failures = [var.sandbox_blocked_destinations]
}

run "blocked_destination_not_ipv6" {
  command = plan

  variables {
    sandbox_blocked_destinations = ["fd00::/8"]
  }

  expect_failures = [var.sandbox_blocked_destinations]
}

run "runner_image_without_tag" {
  command = plan

  variables {
    runner_image = "public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0"
  }

  expect_failures = [var.runner_image]
}

# Subnets in two VPCs have no run: it would override one subnet of
# data.aws_subnet.this, and OpenTofu takes no instance key in an override
# target (tofu init fails on the whole file).

# Temporal takes no key, so its address must be private.
run "public_address_refused" {
  command = plan

  variables {
    temporal_address = "198.51.100.7:7233"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "public_name_refused" {
  command = plan

  variables {
    temporal_address = "temporal.acme.example:7233"
  }

  expect_failures = [terraform_data.validate_inputs]
}

# Only names under a domain count, not names that end the same way.
run "name_beside_private_dns_domain_refused" {
  command = plan

  variables {
    temporal_address    = "runner.notacme.internal:7233"
    private_dns_domains = ["acme.internal"]
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "internet_facing_load_balancer_refused" {
  command = plan

  override_data {
    target = data.aws_lb.address
    values = { internal = false, dns_name = "acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com" }
  }

  expect_failures = [terraform_data.validate_inputs]
}

# A load balancer of the same name elsewhere (another id) is not the one found.
run "load_balancer_of_another_account_refused" {
  command = plan

  variables {
    temporal_address = "acme-prod-autoheal-runner-fedcba9876543210.elb.us-west-2.amazonaws.com:7233"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "http_tool_results_must_be_private" {
  command = plan

  variables {
    tool_response_url = "http://198.51.100.7:8083/api/v1/internal/sandbox-tool-responses"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "repository_prefix_needs_a_registry" {
  command = plan

  variables {
    ecr_repository_prefix = "acme-prod-autoheal"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "trusted_ca_certificate_must_be_pem" {
  command = plan

  variables {
    trusted_ca_certificates = ["-----BEGIN CERTIFICATE-----\nplaceholder-ca\n"]
  }

  expect_failures = [var.trusted_ca_certificates]
}
