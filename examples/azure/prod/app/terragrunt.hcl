# Installs the chart. This file does not change: the chart version comes from
# versions.hcl, the infra values from the infra folder's outputs, and your
# settings from values-customer.yaml next to it.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/app?ref=v${local.v.infra_version}"
}

# Runs after ../infra and reads its outputs.
dependency "infra" {
  config_path = "../infra"

  # Before the first apply there are no outputs yet. The plan uses these
  # placeholders; the apply always uses the real outputs.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    autoheal_values = {}
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
  cluster         = dependency.infra.outputs.cluster
  customer_values = file("${get_terragrunt_dir()}/values-customer.yaml")

  # Defaults, shown for reference:
  # namespace            = "autoheal"
  # chart_repository     = "oci://public.ecr.aws/e4h3h0d9/charts" # or your mirror
  # kubelogin_login_mode = "azurecli"                             # workloadidentity in a federated pipeline
}
