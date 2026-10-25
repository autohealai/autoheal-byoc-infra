# The runner step, optional and applied after the app. Runner VMs run runner-go
# on a VM scale set (modules/azure/runner-vmss) and poll Temporal at
# temporal_address.
#
# By default the runner reaches Temporal through the edge, on the chart's
# runner host (global.edge.runner.host) on 443, over TLS. It sends the runner
# key (temporal_token, the runner_token output of compositions/azure) with each
# call, and the chart's proxy refuses calls without it. Tool results go through
# Temporal too. With temporal_tls = false it reaches the chart's runner load
# balancers on a private address instead, with no TLS and no key.
#
# The runner only dials out. This composition never reads the cluster or its
# subscription: the address is an input, and the network owner opens the path
# listed in required_network_owner_actions. Until then the runner keeps
# retrying. Turn sandboxes on in the chart (global.sandbox.enabled) only after
# the runner shows up as a poller.
#
# The image is <runner_image>:chart-<chart_version>, the tag published with each
# chart release. The VMs retry the pull until it succeeds, so the image may be
# pushed to a new registry after the apply.

locals {
  # null-label id, e.g. acme-prod-autoheal. Resources add a -runner suffix.
  id = lower(join("-", compact([var.namespace, var.environment, var.name])))

  # --- Create or bring ------------------------------------------------------

  create_resource_group = var.existing_resource_group_id == ""
  create_network        = var.existing_subnet_id == ""

  resource_group_name = local.create_resource_group ? (
    var.resource_group_name != "" ? var.resource_group_name : "rg-${var.namespace}-${var.environment}-${var.name}-runner"
  ) : split("/", var.existing_resource_group_id)[4]

  # --- Temporal and tool results --------------------------------------------

  temporal_host = split(":", var.temporal_address)[0]
  temporal_port = split(":", var.temporal_address)[1]

  # Empty sends tool results through Temporal.
  tool_response_url = var.tool_response_url

  # Scheme, host and port of tool_response_url, for the network rule.
  tool_response      = local.tool_response_url == "" ? null : regex("^(https?)://([^/:]+)(?::([0-9]+))?", local.tool_response_url)
  tool_response_host = local.tool_response == null ? "" : local.tool_response[1]
  tool_response_port = local.tool_response == null ? "" : coalesce(local.tool_response[2], local.tool_response[0] == "https" ? "443" : "80")

  # --- Image ----------------------------------------------------------------

  runner_image = "${var.runner_image}:${var.runner_image_tag != "" ? var.runner_image_tag : "chart-${var.chart_version}"}"

  # The ACR name, from its resource ID. The VMs log in to it only when the
  # runner image comes from it (<name>.azurecr.io/...); public images need no
  # login.
  acr_name        = var.acr_id == "" ? "" : lower(split("/", var.acr_id)[8])
  runner_uses_acr = local.acr_name != "" && startswith(lower(var.runner_image), "${local.acr_name}.azurecr.")

  # --- Role grants ----------------------------------------------------------

  required_role_assignments = var.acr_id != "" && !var.create_role_assignments ? [
    "AcrPull on ${local.acr_name} for ${module.runner.identity_name} (principal ID ${module.runner.identity_principal_id})",
  ] : []
}

resource "azurerm_resource_group" "this" {
  count    = local.create_resource_group ? 1 : 0
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

locals {
  # Referencing the resource, not just the name, orders creation after the group.
  rg = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
}

# Plan-time checks with plain messages. (Input validation blocks cannot refer to
# other variables on Terraform 1.7, so checks that combine inputs live here.)
resource "terraform_data" "validate_inputs" {
  lifecycle {
    precondition {
      condition     = local.create_network || lower(try(split("/", var.existing_subnet_id)[2], "")) == lower(var.subscription_id)
      error_message = "existing_subnet_id is in subscription ${try(split("/", var.existing_subnet_id)[2], "")}, but the runner VMs go in subscription_id (${var.subscription_id}). Azure puts a VM's network interface only in a subnet of its own subscription."
    }
    precondition {
      condition     = var.temporal_tls || !local.temporal_public
      error_message = "temporal_address (${local.temporal_host}) is a public address and temporal_tls is false. Without TLS Temporal has no key check, and the traffic carries git tokens and command output, so the runner load balancers take a private route only. To cross the internet, use the chart's runner host with temporal_tls = true."
    }
    precondition {
      condition     = !var.temporal_tls || nonsensitive(var.temporal_token != "")
      error_message = "temporal_token is required with temporal_tls: the chart's proxy refuses runner calls without the key. Pass the runner_token output of compositions/azure."
    }
    precondition {
      condition     = var.temporal_tls || nonsensitive(var.temporal_token == "")
      error_message = "temporal_token is set but temporal_tls is false: the key would cross the network in plain text. Turn temporal_tls on, or leave the key empty for the runner load balancers."
    }
  }
}

locals {
  # A temporal_address host that is an IPv4 address outside the private ranges.
  # A host name is not checked.
  temporal_is_ip = can(cidrhost("${local.temporal_host}/32", 0))
  temporal_public = !local.temporal_is_ip ? false : !anytrue([
    for r in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"] :
    cidrhost("${local.temporal_host}/${split("/", r)[1]}", 0) == split("/", r)[0]
  ])
}

# SSH key for the runner VMs when the customer passes none. The private half is
# kept only in the Terraform state.
resource "tls_private_key" "runner" {
  count     = var.admin_ssh_public_key == "" ? 1 : 0
  algorithm = "ED25519"
}

module "runner" {
  source = "../../modules/azure/runner-vmss"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["runner"]
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location
  subnet_id           = local.subnet_id

  temporal_host              = var.temporal_address
  temporal_tls               = var.temporal_tls
  temporal_server_name       = var.temporal_server_name
  temporal_token             = var.temporal_token
  temporal_ca_certificate    = var.temporal_ca_certificate
  tool_response_callback_url = local.tool_response_url
  runner_image               = local.runner_image
  sandbox_image              = var.sandbox_image
  runner_name                = "${local.id}-runner"
  vm_sku                     = var.vm_size
  os_disk_size_gb            = var.os_disk_size_gb
  max_concurrent_activities  = var.max_concurrent_activities
  instance_count             = var.instance_count

  # Manual, so an apply that changes the image or settings updates and reimages
  # each instance (azurerm features roll_instances_when_required and
  # reimage_on_manual_upgrade, both on by default). Automatic starts a rolling
  # OS upgrade, which fails without a health probe.
  upgrade_mode = "Manual"

  admin_ssh_public_key = var.admin_ssh_public_key != "" ? var.admin_ssh_public_key : tls_private_key.runner[0].public_key_openssh

  # AcrPull is gated on plan-time inputs. The VMs log in to the registry only
  # when the runner image comes from it.
  acr_id           = var.acr_id
  acr_pull_enabled = var.acr_id != "" && var.create_role_assignments
  acr_name         = local.runner_uses_acr ? local.acr_name : ""
}
