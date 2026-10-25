# The sandbox runner, optional: VMs in the data subscription that run the
# commands the agents send. See the README of compositions/azure-runner, and
# step 4 of docs/azure-shared-istio-quickstart.md.
#
# The runner reaches Temporal through the shared Istio gateway, on a hostname
# of its own, with TLS and the runner key. The chart's proxy passes a call on
# to Temporal only when it carries the key. Before you apply this unit:
#   1. Apply ../infra: it makes the runner key (vault entry runner-token).
#   2. Ask the gateway owner to add runner.autoheal.acme.example to the
#      gateway's hosts and certificate and point it at the gateway like the app
#      hostnames. The runner's calls are gRPC: every hop in front of the
#      gateway, a WAF included, must offer TLS 1.3, pass HTTP/2, keep a call
#      open for more than a minute (a Temporal poll lasts about one) and take
#      requests over 1 MB (large tool results).
#   3. In ../app/values-customer.yaml set global.edge.runner.host to that host,
#      then apply ../app.
# Then apply this unit. The runner reaches the gateway through its NAT gateway,
# so no VNet connection is needed. If the gateway is reachable only from
# inside your network, set existing_subnet_id to a subnet with a route to it.
#
# Once the runner polls Temporal, set global.sandbox.enabled to true in
# ../app/values-customer.yaml and apply ../app again.

locals {
  v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals

  # The chart's global.edge.runner.host.
  runner_host = "runner.autoheal.acme.example"
}

include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure-runner?ref=v${local.v.infra_version}"
}

# The runner key. This unit reads nothing else from ../infra.
dependency "infra" {
  config_path = "../infra"

  # Before ../infra is applied there are no outputs yet, and an install still
  # on 4.0.x has outputs but no runner_token. The plan uses this placeholder
  # for what is missing (shallow); the apply always uses the real key.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs = {
    runner_token = "pendingpendingpendingpendingpending"
  }
}

inputs = {
  namespace   = "acme"
  environment = "prod"
  location    = "eastus2" # the cluster's region

  # The data subscription, as in ../infra.
  subscription_id = "11111111-2222-3333-4444-555555555555"

  temporal_address = "${local.runner_host}:443"
  temporal_token   = dependency.infra.outputs.runner_token

  # The CA of the certificate the runner sees on runner.autoheal.acme.example,
  # when a private CA signed it: the same file as edge_ca_certificate in
  # ../infra. Public CAs need nothing here.
  # temporal_ca_certificate = file("${get_terragrunt_dir()}/edge-ca.pem")

  # The runner image is runner-go:chart-<chart_version>, so it moves with the
  # chart.
  chart_version = local.v.chart_version

  # Address range of the runner VNet.
  address_space = "10.61.0.0/24"
}
