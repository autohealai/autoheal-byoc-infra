# Runs of modules/aws/runner-asg on its own: the runner instances' cloud-init.
# Nothing here reaches AWS.
#
# The files in fixtures/ are the reviewed cloud-init, rendered from the
# template with the inputs below: one with the defaults (the runner load
# balancer, public images, no proxy), one with every option (private ECR,
# proxy, more blocked destinations, sandbox pre-pull, private CAs). A change to the
# cloud-init rolls every runner instance, so it must match them byte for byte;
# update a fixture only on purpose.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com", reverse_dns_prefix = "com.amazonaws" }
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
  namespace   = "acme"
  environment = "prod"
  name        = "autoheal"
  attributes  = ["runner"]

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  temporal_host              = "acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:7233"
  tool_response_callback_url = "http://acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:8083/api/v1/internal/sandbox-tool-responses"
  runner_image               = "public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0"
  runner_name                = "acme-prod-autoheal-runner"
}

# The runner load balancer, public images, no proxy.
run "defaults" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  assert {
    condition     = local.user_data == file("tests/fixtures/cloud-init-default.yaml")
    error_message = "The cloud-init must match fixtures/cloud-init-default.yaml byte for byte."
  }

  assert {
    condition     = aws_launch_template.this.user_data == base64gzip(file("tests/fixtures/cloud-init-default.yaml"))
    error_message = "The user data must be the gzipped cloud-init, in base64."
  }

  assert {
    condition     = strcontains(local.user_data, "TEMPORAL_TLS=false\n      TEMPORAL_TOKEN=\n")
    error_message = "The runner connects as Autoheal's hosted runners do: no TLS and an empty TEMPORAL_TOKEN."
  }

  assert {
    condition     = local.sandbox_blocked_destinations == tolist(["acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com"])
    error_message = "Sandboxes are kept off the Temporal and tool-result host, listed once when it is the same."
  }

  assert {
    condition     = length(local.inline_policies) == 0
    error_message = "With public images the role needs no inline policy: there is no key to read."
  }
}

# Every option the template has.
run "all_options" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    sandbox_blocked_destinations = ["10.60.0.0/16", "10.60.15.253", "api.eks.acme.internal"]
    runner_image                 = "123456789012.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9/app/runner-go:chart-1.0.0"
    sandbox_image                = "123456789012.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9/app/sandbox:chart-1.0.0"
    ecr_registry_host            = "123456789012.dkr.ecr.us-west-2.amazonaws.com"
    http_proxy                   = "http://proxy.acme.example:8080"
    no_proxy                     = [".acme.example", "10.0.0.0/8"]
    max_concurrent_activities    = 10
    trusted_ca_certificates = [
      "-----BEGIN CERTIFICATE-----\nplaceholder-registry-ca\n-----END CERTIFICATE-----\n",
      "\r\n-----BEGIN CERTIFICATE-----\r\nplaceholder-proxy-ca\r\n-----END CERTIFICATE-----\r\n",
    ]
  }

  assert {
    condition     = local.user_data == file("tests/fixtures/cloud-init-all-options.yaml")
    error_message = "The cloud-init must match fixtures/cloud-init-all-options.yaml byte for byte."
  }

  assert {
    condition     = yamldecode(local.user_data).ca_certs.trusted == ["-----BEGIN CERTIFICATE-----\nplaceholder-registry-ca\n-----END CERTIFICATE-----\n", "-----BEGIN CERTIFICATE-----\nplaceholder-proxy-ca\n-----END CERTIFICATE-----\n"]
    error_message = "Each CA is one ca_certs.trusted entry, with Windows line ends and outer blank lines removed."
  }

  assert {
    condition     = local.sandbox_blocked_destinations == tolist(["acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com", "10.60.0.0/16", "10.60.15.253", "api.eks.acme.internal"])
    error_message = "The runner load balancer comes first, then sandbox_blocked_destinations."
  }

  assert {
    condition     = jsondecode(local.inline_policies["ecr-pull"]).Statement[1].Resource == "arn:aws:ecr:us-west-2:123456789012:repository/*"
    error_message = "Without ecr_repository_prefix the ecr-pull policy covers every repository of ecr_registry_host."
  }
}

# A long block list with every other option still fits the 16 KB user data
# limit once gzipped. Uncompressed it would not.
run "long_block_list_fits" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    sandbox_blocked_destinations = [for i in range(600) : "10.${60 + floor(i / 256)}.${i % 256}.0/24"]
    runner_image                 = "123456789012.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9/app/runner-go:chart-1.0.0"
    sandbox_image                = "123456789012.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9/app/sandbox:chart-1.0.0"
    ecr_registry_host            = "123456789012.dkr.ecr.us-west-2.amazonaws.com"
    http_proxy                   = "http://proxy.acme.example:8080"
    no_proxy                     = [".acme.example", "10.0.0.0/8"]
  }

  assert {
    condition     = length(local.user_data) > 16384 && length(aws_launch_template.this.user_data) <= 21848
    error_message = "A long block list must fit the user data limit through gzip."
  }
}

# The module writes ecr-pull itself.
run "reserved_inline_policy_names" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    additional_inline_policies = { ecr-pull = "{}" }
  }

  expect_failures = [var.additional_inline_policies]
}

run "trusted_ca_certificate_must_be_pem" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    trusted_ca_certificates = ["placeholder-ca"]
  }

  expect_failures = [var.trusted_ca_certificates]
}
