# The Temporal step, for an install whose cluster cannot host Temporal. One VM
# (modules/azure/temporal-vm) runs the Temporal server against the install's
# Postgres, and a proxy on the VM takes calls on <public IP>:7233 over TLS.
#
# This composition makes what the VM and its clients share: the app key, a
# private CA and the proxy's certificate for temporal.autoheal.internal. The
# runner key comes in as runner_token, the runner_token output of
# compositions/azure. It also lets the VM's public IP through the Postgres
# firewall, and with key_vault_id writes the app key and the CA to a vault.
#
# Clients dial the IP and check the certificate against temporal.autoheal.internal,
# so no DNS record is needed. The outputs feed compositions/azure-runner
# (temporal_address, temporal_server_name, temporal_ca_certificate) and the
# app's chart values.
#
# start_temporal is false by default: the VM comes up with the proxy only. Set
# it to true when the app is ready to move to this Temporal. That replaces the
# VM; the public IP stays.

locals {
  # null-label id, e.g. acme-prod-autoheal. Resources add a -temporal suffix.
  id = lower(join("-", compact([var.namespace, var.environment, var.name])))

  # The name in the proxy's certificate. Clients dial the IP and check this name.
  server_name = "temporal.autoheal.internal"

  create_resource_group = var.existing_resource_group_id == ""

  resource_group_name = local.create_resource_group ? (
    var.resource_group_name != "" ? var.resource_group_name : "rg-${var.namespace}-${var.environment}-${var.name}-temporal"
  ) : split("/", var.existing_resource_group_id)[4]
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
      condition     = local.create_resource_group || lower(try(split("/", var.existing_resource_group_id)[2], "")) == lower(var.subscription_id)
      error_message = "existing_resource_group_id is in subscription ${try(split("/", var.existing_resource_group_id)[2], "")}, but the VM goes in subscription_id (${var.subscription_id}). The azurerm provider of this composition works in subscription_id only."
    }
    precondition {
      condition     = lower(try(split("/", var.postgres_server_id)[2], "")) == lower(var.subscription_id)
      error_message = "postgres_server_id is in subscription ${try(split("/", var.postgres_server_id)[2], "")}, but this composition works in subscription_id (${var.subscription_id}). The azurerm provider adds the Postgres firewall rule in its own subscription. Use the subscription of the Postgres server, usually the data subscription of compositions/azure."
    }
  }
}

# --- Keys and certificate -------------------------------------------------------

# The app key: the app sends it as "Bearer <key>" and the proxy lets it into
# every namespace. Letters and digits only, so it is safe in env files.
resource "random_password" "app_key" {
  length  = 64
  special = false
}

# A private CA for the proxy's certificate. Clients trust it through the
# temporal_ca_certificate output. Renewing it (in its last year) means the app
# and the runner must take the new CA, so it lasts 10 years.
resource "tls_private_key" "ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "Autoheal Temporal CA"
    organization = "Autoheal"
  }

  is_ca_certificate     = true
  set_subject_key_id    = true
  validity_period_hours = 87600
  early_renewal_hours   = 8760
  allowed_uses          = ["cert_signing", "crl_signing", "digital_signature"]
}

resource "tls_private_key" "server" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem
  dns_names       = [local.server_name]

  subject {
    common_name  = local.server_name
    organization = "Autoheal"
  }
}

# Two years. The first apply in its last 90 days makes a new one, which is in
# the VM's custom data, so that apply replaces the VM. Clients keep working:
# the CA stays.
resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  set_subject_key_id    = true
  validity_period_hours = 17520
  early_renewal_hours   = 2160
  allowed_uses          = ["digital_signature", "server_auth"]
}

# SSH key for the VM's admin user. Password login is off and the NSG lets no
# SSH in, so the key only satisfies Azure. The private half stays in the state.
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

# --- VM ---------------------------------------------------------------------

module "temporal_vm" {
  source = "../../modules/azure/temporal-vm"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["temporal"]
  tags        = var.tags

  resource_group_name = local.rg
  location            = var.location

  address_space        = var.address_space
  allowed_source_cidrs = var.allowed_source_cidrs
  vm_size              = var.vm_size
  start_temporal       = var.start_temporal

  temporal_server_image      = var.temporal_server_image
  temporal_admin_tools_image = var.temporal_admin_tools_image
  proxy_image                = var.proxy_image

  postgres_fqdn        = var.postgres_fqdn
  temporal_db_password = var.temporal_db_password

  app_key         = random_password.app_key.result
  runner_token    = var.runner_token
  tls_certificate = tls_locally_signed_cert.server.cert_pem
  tls_private_key = tls_private_key.server.private_key_pem

  admin_ssh_public_key = tls_private_key.ssh.public_key_openssh

  depends_on = [terraform_data.validate_inputs]
}

# --- Postgres ---------------------------------------------------------------

# Lets the VM's public IP into the Postgres server. The server must take public
# connections (compositions/azure with a public Postgres server); a server
# reachable only from its VNet has no firewall rules.
resource "azurerm_postgresql_flexible_server_firewall_rule" "temporal" {
  name             = "${local.id}-temporal"
  server_id        = var.postgres_server_id
  start_ip_address = module.temporal_vm.public_ip
  end_ip_address   = module.temporal_vm.public_ip
}

# --- Key Vault --------------------------------------------------------------

# With key_vault_id, the app key and the CA also go to a vault, for the app's
# chart values to read. The deployer needs Key Vault Secrets Officer on it.
resource "azurerm_key_vault_secret" "app_key" {
  count        = var.key_vault_id == null ? 0 : 1
  name         = "temporal-app-key"
  value        = random_password.app_key.result
  key_vault_id = var.key_vault_id
  content_type = "text/plain"
  tags         = var.tags
}

resource "azurerm_key_vault_secret" "ca" {
  count        = var.key_vault_id == null ? 0 : 1
  name         = "temporal-ca"
  value        = tls_self_signed_cert.ca.cert_pem
  key_vault_id = var.key_vault_id
  content_type = "text/plain"
  tags         = var.tags
}
