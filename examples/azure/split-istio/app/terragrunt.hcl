# Installs the chart in the cluster's Autoheal namespace. The cluster owner
# creates the namespace and gives the deployer rights in it only, so the release
# does not create it.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/app?ref=v${local.v.infra_version}"
}

# Runs after ../infra and ../cluster and reads their outputs.
dependency "infra" {
  config_path = "../infra"

  # Before the first apply there are no outputs yet. The plan uses these
  # placeholders; the apply always uses the real outputs.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    autoheal_values = {}
  }
}

# The cluster's endpoint and CA certificate. ../infra does not read the cluster,
# so its cluster output has them empty.
dependency "cluster" {
  config_path = "../cluster"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    cluster = {
      cloud          = "azure"
      name           = "pending"
      resource_group = "pending"
      endpoint       = "https://pending"
      ca_certificate = ""
    }
  }
}

inputs = {
  chart_version   = local.v.chart_version
  infra_values    = dependency.infra.outputs.autoheal_values
  cluster         = dependency.cluster.outputs.cluster
  customer_values = file("${get_terragrunt_dir()}/values-customer.yaml")

  # The namespace the cluster owner gives you. It exists already, and the
  # deployer may not create namespaces. Keep it the same as
  # service_accounts.namespace in ../infra/terragrunt.hcl.
  namespace        = "autoheal"
  create_namespace = false

  # kubelogin_login_mode = "workloadidentity" # in a federated pipeline
}
