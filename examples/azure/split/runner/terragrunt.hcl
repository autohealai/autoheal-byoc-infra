# The sandbox runner, optional: VMs in the data subscription that run the
# commands the agents send. See the README of compositions/azure-runner.
#
# The runner reaches Temporal through the edge, on a hostname of its own, with
# TLS and the runner key. Before you apply this unit:
#   1. Apply ../infra: it makes the runner key (vault entry runner-token).
#   2. Point runner.autoheal.acme.example at the edge like the app hostnames,
#      and make sure the edge certificate covers it. With a shared Istio
#      Gateway, it must list the host.
#   3. In ../app/values-customer.yaml set global.edge.runner.host to that host,
#      then apply ../app.
# Then apply this unit. The network owner opens the path in the
# required_network_owner_actions output. Until then the runner keeps retrying.
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
  location    = "eastus2"

  # The data subscription, as in ../infra.
  subscription_id = "11111111-2222-3333-4444-555555555555"

  temporal_address = "${local.runner_host}:443"
  temporal_token   = dependency.infra.outputs.runner_token

  # The CA of the edge certificate, when a private CA signed it. Public CAs
  # need nothing here.
  # temporal_ca_certificate = file("${get_terragrunt_dir()}/edge-ca.pem")

  # The runner image is runner-go:chart-<chart_version>, so it moves with the
  # chart.
  chart_version = local.v.chart_version

  # Address range of the runner VNet. It must not overlap vnet-cop, the VNet of
  # ../infra (network_cidr) or anything else connected to them.
  address_space = "10.61.0.0/24"

  # A subnet that already reaches the edge, instead of the VNet above.
  # existing_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-net/providers/Microsoft.Network/virtualNetworks/vnet-acme-spoke/subnets/snet-autoheal-runner"
}
