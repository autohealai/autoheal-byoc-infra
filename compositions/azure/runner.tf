# Runner VMs: runner-go on a VM scale set in the runner subnet, created in this
# apply. They connect to Temporal at the reserved internal address, which the chart
# later pins the Temporal load balancer to, and post sandbox tool results to the
# api-server-go internal listener on port 8083 of the same address. Until the
# chart is installed the runner keeps retrying.
#
# The image is runner-go:chart-<autoheal_version>, so bumping autoheal_version
# changes the runner in the infra plan and the chart in the app plan.
# runner_image_repository and runner_image_tag override it. The VMs retry the
# pull until it succeeds, so the image may be pushed to a new registry after the
# first apply.

module "runner" {
  source = "../../modules/azure/runner-vmss"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["runner"]
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location
  subnet_id           = local.runner_subnet_id

  temporal_host              = "${local.temporal_ip}:7233"
  tool_response_callback_url = local.tool_response_callback_url
  runner_image               = local.runner_image
  sandbox_image              = var.runner_sandbox_image
  runner_name                = "${local.id}-runner"
  vm_sku                     = var.runner_vm_size
  instance_count             = var.runner_node_count

  # Apply a new image or settings to every instance in the same apply.
  upgrade_mode = "Automatic"

  admin_ssh_public_key = var.runner_admin_ssh_public_key != "" ? var.runner_admin_ssh_public_key : tls_private_key.runner[0].public_key_openssh

  # The runner identity may pull from the registry when there is one (gated on
  # plan-time inputs). The VMs log in to it only when the runner image comes
  # from it; the default public images need no login.
  acr_id           = local.acr_id
  acr_pull_enabled = local.acr_enabled && var.create_role_assignments
  acr_name         = local.runner_uses_acr ? local.acr_name : ""
}

locals {
  # The chart puts the api-server-go internal listener on the Temporal address,
  # port 8083 (api-server-go-internal-lb). The runners post tool results there.
  tool_response_callback_url = "http://${local.temporal_ip}:8083/api/v1/internal/sandbox-tool-responses"

  runner_image    = "${var.runner_image_repository}:${var.runner_image_tag != "" ? var.runner_image_tag : "chart-${var.autoheal_version}"}"
  runner_uses_acr = local.acr_enabled && startswith(lower(var.runner_image_repository), "${lower(local.acr_name)}.azurecr.io/")
}
