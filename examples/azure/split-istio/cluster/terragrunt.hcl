# Reads the cluster after ../infra, checks that it has what Autoheal needs, and
# federates the three workload identities to its OIDC issuer, so pods in the
# Autoheal namespace can sign in as them. ../infra never reads the cluster;
# this unit is where the cluster comes in. ../app takes the cluster's endpoint
# and CA certificate from here.
#
# Whoever runs it needs Azure Kubernetes Service Cluster User Role on the
# cluster (the required_cluster_owner_actions output of ../infra lists it), and
# write on the workload identities in the data subscription, which the
# principal that ran ../infra has.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure-cluster?ref=v${local.v.infra_version}"
}

# Runs after ../infra and reads its outputs.
dependency "infra" {
  config_path = "../infra"

  # Before the first apply there are no outputs yet. The plan uses these
  # placeholders; the apply always uses the real outputs.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    cluster = {
      cloud           = "azure"
      name            = "pending"
      resource_group  = "pending"
      subscription_id = "00000000-0000-0000-0000-000000000000"
      endpoint        = ""
      ca_certificate  = ""
    }
    federation = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      identities      = {}
    }
  }
}

inputs = {
  cluster    = dependency.infra.outputs.cluster
  federation = dependency.infra.outputs.federation

  # Only when upgrading an install from infra 3.x, and for one apply: take over
  # the federated credentials ../infra made instead of creating them, so pods
  # keep signing in through the upgrade. See the README of
  # compositions/azure-cluster for the state commands to run first.
  # import_federated_credentials = true
}
