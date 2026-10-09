# Azure VMSS runner — the AKS analogue of the EKS EC2/ASG runner. A VM in the
# runner subnet runs the runner-go worker as a container (Docker-out-of-Docker: it
# drives the host Docker daemon via the mounted socket to launch sandbox
# containers), polling Temporal on the `runners` namespace via the internal LB.
#
# This is a SEPARATE unit from the main composition on purpose: it needs
# temporal_host, which only exists after the cluster + Temporal are deployed and the
# internal LB is assigned an IP (discover-and-feed-forward) — mirroring how the AWS
# runner unit runs after temporal-nlb. The runner subnet + its NAT egress live in
# modules/azure/vnet.
#
# Identity: a user-assigned MI (some policies forbid system-assigned on VMs/VMSS),
# granted only AcrPull — the runner pulls images via managed identity and holds no
# static registry creds. It does NOT read Key Vault (in-cluster apps do, via
# workload identity); the runner's only secret-bearing config is the Temporal
# endpoint. Naming and tags come from the null-label base (module.this); see label.tf.

resource "azurerm_user_assigned_identity" "runner" {
  name                = "${module.this.id}-uai"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

resource "azurerm_linux_virtual_machine_scale_set" "runner" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.vm_sku
  instances           = var.instance_count
  admin_username      = var.admin_username
  upgrade_mode        = "Manual"
  overprovision       = false

  # Managed-identity ACR auth; host az login --identity uses this client id.
  custom_data = base64encode(templatefile("${path.module}/cloudinit.yaml.tftpl", {
    temporal_host             = var.temporal_host
    runner_image              = var.runner_image
    sandbox_image             = var.sandbox_image
    runner_name               = var.runner_name
    max_concurrent_activities = var.max_concurrent_activities
    uami_client_id            = azurerm_user_assigned_identity.runner.client_id
    acr_name                  = var.acr_name
  }))

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

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = var.os_disk_size_gb
  }

  # No public IP: egress flows through the runner subnet's NAT gateway (vnet module).
  network_interface {
    name    = "${module.this.id}-nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = var.subnet_id
    }
  }

  tags = module.this.tags

  # AcrPull must exist before boot, or the first image pull fails before the hourly
  # credential-refresh timer can recover it.
  depends_on = [azurerm_role_assignment.acr_pull]
}
