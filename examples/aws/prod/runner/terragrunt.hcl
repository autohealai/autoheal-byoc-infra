# The sandbox runner, optional: EC2 instances in the private subnets that run
# the commands the agents send. See the README of compositions/aws-runner.
#
# The runner reaches Temporal the way Autoheal's hosted runners do: on the
# internal runner load balancer of ../infra, with no TLS and no key. Before you
# apply this unit:
#   1. Set runner_lb_enabled = true in ../infra and apply it: it makes the load
#      balancer and turns on its two listeners in the chart values.
#   2. Apply ../app, so the chart binds Temporal and the tool-result listener
#      to the load balancer.
# Then apply this unit. The network owner opens the path in the
# required_network_owner_actions output. Until then the runner keeps retrying.
#
# Once the runner polls Temporal, set global.sandbox.enabled to true in
# ../app/values-customer.yaml and apply ../app again.

locals {
  v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals
}

include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/aws-runner?ref=v${local.v.infra_version}"
}

# The runner load balancer and the subnets. This unit reads nothing else from
# ../infra.
dependency "infra" {
  config_path = "../infra"

  # An install still on 4.5.x has outputs but no runner_load_balancer. The plan
  # uses these placeholders for what is missing (shallow); the apply always
  # uses the real outputs. They are private addresses so that the plan passes
  # its checks. Before ../infra is applied at all, the plan of this unit stops
  # at the subnet lookup, so plan it once ../infra is applied.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs = {
    runner_load_balancer = {
      temporal_address  = "10.255.255.254:7233"
      tool_response_url = "http://10.255.255.254:8083/api/v1/internal/sandbox-tool-responses"
    }
    network = { private_subnet_ids = ["subnet-00000000000000000"] }
  }
}

inputs = {
  namespace   = "acme"
  environment = "prod"
  account_id  = "111111111111"
  region      = "us-west-2"

  # Temporal on 7233 and tool results on 8083, on the runner load balancer.
  temporal_address  = dependency.infra.outputs.runner_load_balancer.temporal_address
  tool_response_url = dependency.infra.outputs.runner_load_balancer.tool_response_url

  # More destinations sandboxes may not reach, on top of the load balancer,
  # such as the VPC range or the cluster API endpoint.
  # sandbox_blocked_destinations = ["10.60.0.0/16"]

  # The private subnets of ../infra. With existing_network there, these are the
  # subnets you passed; any private subnets of that VPC with a route to the
  # runner load balancer will do.
  subnet_ids = dependency.infra.outputs.network.private_subnet_ids

  # The runner image is runner-go:chart-<chart_version>, so it moves with the
  # chart.
  chart_version = local.v.chart_version

  # Images from your own registry instead of the public one. With a private
  # ECR registry (such as the pull-through cache of ../infra), the instance
  # role gets pull rights on it.
  # runner_image          = "111111111111.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9/app/runner-go"
  # sandbox_image         = "111111111111.dkr.ecr.us-west-2.amazonaws.com/acme-prod-autoheal/e4h3h0d9/app/sandbox:<tag>"
  # ecr_registry_host     = "111111111111.dkr.ecr.us-west-2.amazonaws.com"
  # ecr_repository_prefix = "acme-prod-autoheal"

  # Subnets whose way out is a proxy. Sandboxes do not get it. With VPC
  # endpoints for ECR or SSM, list their names in no_proxy.
  # http_proxy = "http://proxy.acme.example:8080"
  # no_proxy   = [".acme.example", "10.0.0.0/8"]

  # A registry or a TLS-inspecting proxy whose certificate a private CA signs:
  # its CA, added to the instances' trust store.
  # trusted_ca_certificates = [file("${get_terragrunt_dir()}/nexus-ca.pem")]

  # Private root CAs of your own systems, such as an internal GitLab: the same
  # PEM as the vault entry of the chart's global.trust.caVaultEntry. The runner
  # and every sandbox it creates trust them on top of the public CAs.
  # custom_ca_certificate = file("${get_terragrunt_dir()}/custom-ca.pem")

  # A company image built from Amazon Linux 2023, instead of the public one.
  # ami_name_filter = "*golden-amzn-linux-2023-v*"
  # ami_owners      = ["111111111111"]

  # Where a central team owns IAM or security groups. The
  # required_role_policies output lists what the brought role needs.
  # existing_instance_profile_arn = "arn:aws:iam::111111111111:instance-profile/acme-autoheal-runner"
  # existing_security_group_id    = "sg-0123456789abcdef0"

  # Access without SSM Session Manager: SSH as ec2-user from a jump host.
  # ssm_enabled             = false
  # key_name                = "acme-autoheal-runner"
  # ssh_ingress_cidr_blocks = ["10.60.200.0/24"]
}
