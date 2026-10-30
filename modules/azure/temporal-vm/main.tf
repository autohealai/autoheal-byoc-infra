# One VM that runs the Temporal server for an install whose cluster cannot host
# it. The app and the runner reach it over the internet on TCP 7233, through a
# proxy on the VM that ends TLS and checks a key, the way the chart's proxy
# guards the runner host. Temporal itself listens on 127.0.0.1 only.
#
# The VM has a static public IP and a VNet of its own that is connected to
# nothing. The NSG lets in TCP 7233 from allowed_source_cidrs and denies the
# rest, SSH included. Temporal keeps its data in Postgres, so the VM holds no
# state and may be replaced at any time.
#
# Everything on the VM comes from cloud-init (cloudinit.yaml.tftpl): Docker, the
# Temporal config, the proxy config with the two keys, the certificate, and four
# systemd units. temporal-schema sets up or upgrades the schema in both
# databases, temporal-server runs Temporal (enabled only with start_temporal),
# temporal-namespaces creates the three namespaces, and temporal-edge runs the
# proxy. Each unit pulls its image and retries until it succeeds.
#
# Any change to the custom data (start_temporal, a key, the certificate, an
# image) replaces the VM. The public IP is a separate resource and stays, so
# clients and firewall rules keep working. The keys, the database password and
# the private key are in the custom data, which Azure never returns on read,
# and in root-only files on the VM. Naming and tags come from the null-label
# base (module.this); see label.tf.

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

# TCP 7233 from the allowed ranges, nothing else. The explicit deny also covers
# Azure's default rules that let in the VNet and the load balancer.
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

# Static, so it survives a VM replacement: clients dial it, and firewalls
# (Postgres, the cluster's egress) let it through.
resource "azurerm_public_ip" "temporal" {
  name                = "${module.this.id}-ip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = module.this.tags
}

resource "azurerm_network_interface" "temporal" {
  name                           = "${module.this.id}-nic"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  accelerated_networking_enabled = true
  tags                           = module.this.tags

  ip_configuration {
    name                          = "internal"
    primary                       = true
    subnet_id                     = azurerm_subnet.temporal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.temporal.id
  }
}

# --- VM ---------------------------------------------------------------------

locals {
  cloud_init = templatefile("${path.module}/cloudinit.yaml.tftpl", {
    start_temporal             = var.start_temporal
    temporal_server_image      = var.temporal_server_image
    temporal_admin_tools_image = var.temporal_admin_tools_image
    proxy_image                = var.proxy_image
    postgres_fqdn              = var.postgres_fqdn
    temporal_db_password       = var.temporal_db_password
    num_history_shards         = var.num_history_shards
    app_key                    = var.app_key
    runner_token               = var.runner_token
    tls_certificate            = var.tls_certificate
    tls_private_key            = var.tls_private_key
  })
}

resource "azurerm_linux_virtual_machine" "temporal" {
  name                            = module.this.id
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.temporal.id]

  # gzip keeps the custom data well under Azure's limit. cloud-init unpacks it.
  # A change here replaces the VM.
  custom_data = base64gzip(local.cloud_init)

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
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

  # Serial log in a managed storage account, the way to read cloud-init output
  # without SSH (az vm boot-diagnostics get-boot-log).
  boot_diagnostics {}

  tags = module.this.tags

  # The VM boots with its NSG in place.
  depends_on = [azurerm_subnet_network_security_group_association.temporal]
}
