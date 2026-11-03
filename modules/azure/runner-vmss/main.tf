# Azure VMSS runner, the AKS analogue of the EKS EC2/ASG runner. A VM in the
# runner subnet runs the runner-go worker as a container (Docker-out-of-Docker: it
# drives the host Docker daemon via the mounted socket to launch sandbox
# containers), polling Temporal on the `runners` namespace.
#
# compositions/azure-runner creates the runner as its own step, after the app.
# temporal_host is the chart's runner host on 443, which the runner dials over
# TLS with the runner key (temporal_token), or the private address of a Temporal
# load balancer. runner-go runs under systemd with
# Restart=always and retries until Temporal answers. Before each start the unit
# pulls the image and keeps retrying with a backoff until the pull succeeds, so
# the image may be pushed to a new registry after the apply without reimaging the
# VMs. The runner subnet and its NAT egress come from compositions/azure-runner
# (or the customer's network).
#
# Identity: a user-assigned MI (some policies forbid system-assigned on VMs/VMSS).
# When images come from an ACR it is granted AcrPull and the host logs in with it,
# and runner-go gets its own login file for the sandbox images it pulls itself;
# when images are public (the default public ECR) no registry login runs. Only
# the host uses the identity: containers on the VM, sandboxes included, cannot
# reach the instance metadata service (block-imds.sh). It does NOT read Key
# Vault; the runner's config is the Temporal endpoint, its key and CA, and
# optionally the api-server-go internal listener it posts tool results to. The
# key is in the custom data, which Azure never returns on read, and in a
# root-only file on the VMs. Naming and tags come from the null-label base
# (module.this); see label.tf.
#
# With temporal_ip (the IP of a Temporal VM from compositions/azure-temporal),
# runner-go runs on a Docker network of its own (runner_network_cidr), and no
# other container on the VM may reach that IP on the port of temporal_host, the
# only port the Temporal VM's load balancer forwards. Sandboxes stay on Docker's
# default bridge; runner-go drives them through the Docker socket, not over the
# network. Empty temporal_ip leaves the custom data as it was.

resource "azurerm_user_assigned_identity" "runner" {
  name                = "${module.this.id}-uai"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.acr_pull_enabled ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

locals {
  # The port after the last colon of temporal_host: 7233 or the Temporal VM's
  # client_port. With temporal_ip, block-imds.sh resets it for other containers.
  temporal_port = reverse(split(":", var.temporal_host))[0]

  # Managed-identity ACR auth; host az login --identity uses this client id.
  cloud_init = templatefile("${path.module}/cloudinit.yaml.tftpl", {
    temporal_host              = var.temporal_host
    temporal_tls               = var.temporal_tls
    temporal_server_name       = var.temporal_server_name
    temporal_token             = var.temporal_token
    temporal_ca_certificate    = var.temporal_ca_certificate
    tool_response_callback_url = var.tool_response_callback_url
    temporal_ip                = var.temporal_ip
    temporal_port              = local.temporal_port
    runner_network_cidr        = var.runner_network_cidr
    runner_image               = var.runner_image
    sandbox_image              = var.sandbox_image
    runner_name                = var.runner_name
    max_concurrent_activities  = var.max_concurrent_activities
    uami_client_id             = azurerm_user_assigned_identity.runner.client_id
    acr_name                   = var.acr_name
  })
}

resource "azurerm_linux_virtual_machine_scale_set" "runner" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.vm_sku
  instances           = var.instance_count
  admin_username      = var.admin_username
  upgrade_mode        = var.upgrade_mode
  overprovision       = false

  custom_data = base64encode(local.cloud_init)

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runner.id]
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Premium SSD speed grows with size, so the size also sets the IOPS; see
  # var.os_disk_size_gb.
  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = var.os_disk_size_gb
  }

  # No public IP: egress flows through the runner subnet's NAT gateway.
  # Accelerated networking is on, as on the hosted runners; vm_sku must support it.
  network_interface {
    name                          = "${module.this.id}-nic"
    primary                       = true
    enable_accelerated_networking = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = var.subnet_id
    }
  }

  tags = module.this.tags

  lifecycle {
    # The rule for temporal_ip needs the port runner-go dials.
    precondition {
      condition     = var.temporal_ip == "" || can(regex("^[0-9]{1,5}$", local.temporal_port))
      error_message = "temporal_ip is set, so temporal_host must end in :<port>, such as 198.51.100.7:7233: the runner VMs reset that port to temporal_ip for every container but runner-go."
    }
  }

  # AcrPull must exist before boot, or the first image pull fails before the hourly
  # credential-refresh timer can recover it.
  depends_on = [azurerm_role_assignment.acr_pull]
}
