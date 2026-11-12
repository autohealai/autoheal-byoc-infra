# Runs of modules/aws/runner-asg on its own: the runner instances' cloud-init.
# Nothing here reaches AWS.
#
# The files in fixtures/ are the reviewed cloud-init, rendered from the
# template with the inputs below: one with the defaults (the runner load
# balancer, public images, no proxy), one with every option (private ECR,
# proxy, more blocked destinations, sandbox pre-pull, private CAs). A change to the
# cloud-init rolls every runner instance, so it must match them byte for byte;
# update a fixture only on purpose. The fixtures have no custom_ca_certificate:
# its runs check that it adds its file and the CA folder mount, and nothing
# else.

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

# The callback key: the AWS CLI package, the script that reads the key before
# each start, its ExecStartPre and the env file. Taking those out gives the
# default cloud-init again, so the key adds nothing else, and never the key
# itself.
run "callback_key_adds_only_its_parts" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    tool_response_token_secret_arn  = "arn:aws:secretsmanager:us-west-2:123456789012:secret:acme-prod-autoheal/runner-callback-token-AbCdEf"
    tool_response_token_kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/0123abcd-4567-89ef-0123-456789abcdef"
  }

  assert {
    condition     = strcontains([for f in yamldecode(local.user_data).write_files : f.content if f.path == "/usr/local/bin/callback-key.sh"][0], "key=$(aws secretsmanager get-secret-value --region us-west-2 --secret-id 'arn:aws:secretsmanager:us-west-2:123456789012:secret:acme-prod-autoheal/runner-callback-token-AbCdEf' --query SecretString --output text)\n")
    error_message = "callback-key.sh reads the secret in its own region."
  }

  assert {
    condition     = [for l in split("\n", [for f in yamldecode(local.user_data).write_files : f.content if f.path == "/etc/systemd/system/runner-go.service"][0]) : l if startswith(l, "ExecStartPre=")][3] == "ExecStartPre=/usr/local/bin/callback-key.sh"
    error_message = "The key is read last before each start, and a failed read fails the start."
  }

  assert {
    condition = replace(replace(replace(replace(local.user_data,
      "/  - path: /usr/local/bin/callback-key\\.sh\n(    [^\n]*\n)+/", ""),
      "  - awscli-2\n", ""),
      "      # No \"-\": without the callback key the runner does not start.\n      ExecStartPre=/usr/local/bin/callback-key.sh\n", ""),
    "        --env-file /opt/runner-go/callback.env \\\n", "") == file("tests/fixtures/cloud-init-default.yaml")
    error_message = "The callback key adds the package, the script, its ExecStartPre and the env file, and nothing else."
  }
}

# Through the edge, with a proxy and private CAs: the script uses the proxy and
# the system CA bundle, and sandboxes keep the app host.
run "callback_key_through_the_edge" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    tool_response_callback_url      = "https://autoheal.acme.example/api/v1/internal/sandbox-tool-responses"
    tool_response_token_secret_arn  = "arn:aws:secretsmanager:us-west-2:123456789012:secret:acme-prod-autoheal/runner-callback-token-AbCdEf"
    tool_response_token_kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/0123abcd-4567-89ef-0123-456789abcdef"
    http_proxy                      = "http://proxy.acme.example:8080"
    trusted_ca_certificates         = ["-----BEGIN CERTIFICATE-----\nplaceholder-proxy-ca\n-----END CERTIFICATE-----\n"]
  }

  assert {
    condition     = local.sandbox_blocked_destinations == tolist(["acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com"])
    error_message = "An https:// tool-result host is not blocked: it is the edge, which checks the key and serves the app."
  }

  assert {
    condition = alltrue([for s in [
      "set -a; . /opt/runner-go/proxy.env; set +a\n",
      "export AWS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt\n",
    ] : strcontains([for f in yamldecode(local.user_data).write_files : f.content if f.path == "/usr/local/bin/callback-key.sh"][0], s)])
    error_message = "With a proxy and private CAs, callback-key.sh uses the proxy and the system CA bundle."
  }

  assert {
    condition     = contains(yamldecode(local.user_data).packages, "awscli-2")
    error_message = "The AWS CLI is installed."
  }
}

# The role needs the KMS key to read the secret.
run "callback_key_needs_its_kms_key" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    tool_response_token_secret_arn = "arn:aws:secretsmanager:us-west-2:123456789012:secret:acme-prod-autoheal/runner-callback-token-AbCdEf"
  }

  expect_failures = [aws_launch_template.this]
}

# The module writes callback-key itself.
run "reserved_callback_key_policy_name" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    additional_inline_policies = { callback-key = "{}" }
  }

  expect_failures = [var.additional_inline_policies]
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

# With every option, the custom CAs add their file and the CA folder mount, and
# change nothing else.
run "custom_ca_adds_its_file" {
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
    custom_ca_certificate = "-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca-1\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca-2\n-----END CERTIFICATE-----\n"
  }

  assert {
    condition = [for f in yamldecode(local.user_data).write_files : f if f.path == "/opt/runner-go/ca/custom-ca.pem"] == [{
      path        = "/opt/runner-go/ca/custom-ca.pem"
      permissions = "0644"
      content     = "-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca-1\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca-2\n-----END CERTIFICATE-----\n"
    }]
    error_message = "The custom CAs go to /opt/runner-go/ca/custom-ca.pem, 0644, as given."
  }

  assert {
    condition     = length(regexall("-v /opt/runner-go/ca:/opt/runner-go/ca:ro", local.user_data)) == 1
    error_message = "The CA folder is mounted once."
  }

  assert {
    condition     = length(yamldecode(local.user_data).ca_certs.trusted) == 2
    error_message = "The custom CAs stay out of the host's trust store."
  }

  assert {
    condition = replace(replace(local.user_data,
      "  # The customer's private root CAs. runner-go reads this path by default and\n  # mounts them, on top of its public roots, into every sandbox it creates.\n  - path: /opt/runner-go/ca/custom-ca.pem\n    permissions: '0644'\n    content: |\n      -----BEGIN CERTIFICATE-----\n      placeholder-custom-ca-1\n      -----END CERTIFICATE-----\n      -----BEGIN CERTIFICATE-----\n      placeholder-custom-ca-2\n      -----END CERTIFICATE-----\n", ""),
    "        -v /opt/runner-go/ca:/opt/runner-go/ca:ro \\\n", "") == file("tests/fixtures/cloud-init-all-options.yaml")
    error_message = "custom_ca_certificate adds its file and the CA folder mount, and nothing else: no environment variable."
  }
}

run "custom_ca_alone_mounts_the_ca_folder" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    custom_ca_certificate = "-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca\n-----END CERTIFICATE-----\n"
  }

  assert {
    condition     = strcontains([for f in yamldecode(local.user_data).write_files : f.content if f.path == "/etc/systemd/system/runner-go.service"][0], "  -v /opt/runner-go/ca:/opt/runner-go/ca:ro \\\n")
    error_message = "The CA folder is mounted read-only into runner-go."
  }

  assert {
    condition = replace(replace(local.user_data,
      "  # The customer's private root CAs. runner-go reads this path by default and\n  # mounts them, on top of its public roots, into every sandbox it creates.\n  - path: /opt/runner-go/ca/custom-ca.pem\n    permissions: '0644'\n    content: |\n      -----BEGIN CERTIFICATE-----\n      placeholder-custom-ca\n      -----END CERTIFICATE-----\n", ""),
    "        -v /opt/runner-go/ca:/opt/runner-go/ca:ro \\\n", "") == file("tests/fixtures/cloud-init-default.yaml")
    error_message = "custom_ca_certificate alone adds its file and the CA folder mount, and nothing else."
  }
}

# Certificates barely compress, so a long bundle stops at the user data limit.
run "custom_ca_must_fit_the_user_data" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    custom_ca_certificate = "-----BEGIN CERTIFICATE-----\n${join("", [for i in range(600) : "${substr(sha512(tostring(i)), 0, 64)}\n"])}-----END CERTIFICATE-----\n"
  }

  expect_failures = [aws_launch_template.this]
}

run "custom_ca_refuses_a_private_key" {
  command = plan

  module {
    source = "../../modules/aws/runner-asg"
  }

  variables {
    custom_ca_certificate = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n"
  }

  expect_failures = [var.custom_ca_certificate]
}
