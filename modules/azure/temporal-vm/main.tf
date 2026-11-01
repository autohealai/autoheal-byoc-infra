# One VM that runs the Temporal server for an install whose cluster cannot host
# it. The app and the runner reach it over the internet on TCP 7233, through a
# gate on the VM (Envoy) that ends TLS and checks a key per call. Temporal
# itself listens on 127.0.0.1 only.
#
# The VM is the only instance of a scale set behind a Standard public load
# balancer with one static IP. The load balancer forwards TCP 7233 and gives
# the VM its outbound path on the same IP (an outbound rule), so clients and
# firewalls (Postgres, Key Vault, the cluster's egress) see one address. The VM
# has no public IP of its own and a VNet that is connected to nothing. The NSG
# lets in TCP 7233 from allowed_source_cidrs, and the load balancer's probe,
# and denies the rest, SSH included.
#
# The scale set has exactly one instance, upgrade mode Manual and no
# overprovisioning, so Azure never runs two of these VMs at once: two Temporal
# servers on one database would corrupt it. A change to the custom data
# (start_temporal, an image, the runner allow list) updates the scale set model
# only; it reaches the VM when the operator reimages it, in place. The
# composition turns off the provider's automatic roll for that reason.
#
# Everything on the VM comes from cloud-init (cloudinit.yaml.tftpl). The keys
# and the certificate are not in it: a timer reads them from Key Vault with the
# VM's identity at boot and every 5 minutes (scripts/temporal-secrets.sh), and
# the gate reloads them from files without dropping connections. Temporal
# keeps its data in Postgres, so the VM holds no state. The database password
# is in the custom data, which Azure never returns on read, and in a root-only
# file on the VM. Naming and tags come from the null-label base (module.this);
# see label.tf.

locals {
  # The calls every key gets 401 on, even an app key.
  denied_methods = [
    "RegisterNamespace",
    "UpdateNamespace",
    "DeprecateNamespace",
    "StartBatchOperation",
    "DeleteWorkflowExecution",
    "DeleteWorkerDeployment",
    "DeleteWorkerDeploymentVersion",
  ]

  logs_enabled = var.log_analytics_workspace_id != ""
}

# --- Network ----------------------------------------------------------------

resource "azurerm_virtual_network" "temporal" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.address_space]
  tags                = module.this.tags
}

resource "azurerm_subnet" "temporal" {
  name                 = "snet-temporal"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.temporal.name
  address_prefixes     = [var.address_space]
}

# TCP 7233 from the allowed ranges, and the load balancer's probe on 7233 and
# the health port. The explicit deny also covers Azure's default rules that let
# in the VNet and the load balancer on any port.
resource "azurerm_network_security_group" "temporal" {
  name                = "${module.this.id}-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags

  security_rule {
    name                       = "allow-temporal-7233"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "7233"
    source_address_prefixes    = var.allowed_source_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-load-balancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["7233", tostring(var.health_port)]
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "temporal" {
  subnet_id                 = azurerm_subnet.temporal.id
  network_security_group_id = azurerm_network_security_group.temporal.id
}

# --- Load balancer ----------------------------------------------------------

# Static: clients dial it, and firewalls let it through. It stays when the VM
# is reimaged or replaced.
resource "azurerm_public_ip" "temporal" {
  name                = "${module.this.id}-ip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = module.this.tags
}

resource "azurerm_lb" "temporal" {
  name                = "${module.this.id}-lb"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  tags                = module.this.tags

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.temporal.id
  }
}

resource "azurerm_lb_backend_address_pool" "temporal" {
  name            = "temporal"
  loadbalancer_id = azurerm_lb.temporal.id
}

# The gate's health listener answers 200 only while its own gRPC health check
# on Temporal passes. While Temporal is off (start_temporal false, before the
# cutover) the probe fails and the load balancer sends no new connections to
# the VM; checks of the gate then run on the VM itself.
resource "azurerm_lb_probe" "health" {
  name                = "health"
  loadbalancer_id     = azurerm_lb.temporal.id
  protocol            = "Http"
  port                = var.health_port
  request_path        = "/healthz"
  interval_in_seconds = 5
  number_of_probes    = 2
}

# Outbound SNAT is off on this rule: the outbound rule below gives the VM its
# path out on the same IP.
resource "azurerm_lb_rule" "temporal" {
  name                           = "temporal-7233"
  loadbalancer_id                = azurerm_lb.temporal.id
  protocol                       = "Tcp"
  frontend_port                  = 7233
  backend_port                   = 7233
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.temporal.id]
  probe_id                       = azurerm_lb_probe.health.id
  disable_outbound_snat          = true
  floating_ip_enabled            = false
  # Workers hold long polls open on few connections. The reset tells a client
  # at once when the load balancer drops an idle one.
  idle_timeout_in_minutes = 30
  tcp_reset_enabled       = true
}

# The VM's only way out: Postgres, Key Vault, the image registry and the
# package mirror see the load balancer's IP.
resource "azurerm_lb_outbound_rule" "temporal" {
  name                    = "outbound"
  loadbalancer_id         = azurerm_lb.temporal.id
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.temporal.id
  tcp_reset_enabled       = true

  frontend_ip_configuration {
    name = "public"
  }
}

# --- VM ---------------------------------------------------------------------

# The VM's identity. It reads the keys and the certificate from Key Vault (the
# composition grants Key Vault Secrets User on each entry) and signs in the
# Azure Monitor agent. Containers on the VM do not use it.
resource "azurerm_user_assigned_identity" "temporal" {
  name                = "${module.this.id}-uai"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = module.this.tags
}

locals {
  cloud_init = templatefile("${path.module}/cloudinit.yaml.tftpl", {
    start_temporal             = var.start_temporal
    temporal_server_image      = var.temporal_server_image
    temporal_admin_tools_image = var.temporal_admin_tools_image
    proxy_image                = var.proxy_image
    postgres_fqdn              = var.postgres_fqdn
    temporal_db_password       = var.temporal_db_password
    num_history_shards         = var.num_history_shards
    health_port                = var.health_port
    key_vault_uri              = trimsuffix(var.key_vault_uri, "/")
    identity_client_id         = azurerm_user_assigned_identity.temporal.client_id
    api_server_key_secret_name = var.api_server_key_secret_name
    agents_key_secret_name     = var.agents_key_secret_name
    runner_key_secret_name     = var.runner_key_secret_name
    certificate_secret_name    = var.certificate_secret_name
    runner_allowed_methods     = var.runner_allowed_methods
    denied_methods             = local.denied_methods
    logs_enabled               = local.logs_enabled
    secrets_script             = file("${path.module}/scripts/temporal-secrets.sh")
    guard_script               = file("${path.module}/scripts/temporal-guard.sh")
  })
}

resource "azurerm_linux_virtual_machine_scale_set" "temporal" {
  name                = module.this.id
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.vm_size
  admin_username      = var.admin_username

  # One VM, never two. Manual: Azure changes the VM only when told to, and a
  # reimage works in place. No overprovisioning: Azure would otherwise start
  # extra VMs during a scale-out and delete them after.
  instances     = 1
  upgrade_mode  = "Manual"
  overprovision = false

  # gzip keeps the custom data well under Azure's limit. cloud-init unpacks it.
  custom_data = base64gzip(local.cloud_init)

  # No password login, and the NSG lets no SSH in: use az vmss run-command.
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.temporal.id]
  }

  # The same image as the runner VMs.
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

  # No public IP on the VM: inbound and outbound both go through the load
  # balancer's IP.
  network_interface {
    name                          = "${module.this.id}-nic"
    primary                       = true
    enable_accelerated_networking = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.temporal.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.temporal.id]
    }
  }

  # Serial log in a managed storage account, the way to read cloud-init output
  # without SSH (az vmss get-instance-view, or the portal's boot diagnostics).
  boot_diagnostics {}

  # The Azure Monitor agent, signed in with the VM's identity, when logs go to
  # a workspace.
  dynamic "extension" {
    for_each = local.logs_enabled ? [1] : []
    content {
      name                       = "AzureMonitorLinuxAgent"
      publisher                  = "Microsoft.Azure.Monitor"
      type                       = "AzureMonitorLinuxAgent"
      type_handler_version       = "1.0"
      auto_upgrade_minor_version = true
      automatic_upgrade_enabled  = true
      settings = jsonencode({
        authentication = {
          managedIdentity = {
            identifier-name  = "mi_res_id"
            identifier-value = azurerm_user_assigned_identity.temporal.id
          }
        }
      })
    }
  }

  tags = module.this.tags

  lifecycle {
    precondition {
      condition     = length(setintersection(toset(var.runner_allowed_methods), toset(local.denied_methods))) == 0
      error_message = "runner_allowed_methods must not list ${join(", ", local.denied_methods)}: the gate refuses them for every key."
    }
  }

  # The VM boots with its NSG and its outbound path in place: cloud-init
  # installs packages and pulls images through the outbound rule.
  depends_on = [
    azurerm_subnet_network_security_group_association.temporal,
    azurerm_lb_rule.temporal,
    azurerm_lb_outbound_rule.temporal,
  ]
}
