# The Temporal step, for an install whose cluster cannot host Temporal. One VM
# (modules/azure/temporal-vm) runs the Temporal server against the install's
# Postgres, behind a load balancer with one static IP. A gate on the VM takes
# calls on <IP>:7233 over TLS and checks a key per call.
#
# This composition makes what the VM and its clients share, in the install
# vault (key_vault_id): the api-server key and the agents key, and, without
# certificate_name, a private CA and the gate's certificate for
# temporal.autoheal.internal. The runner key is the vault entry runner-token
# that compositions/azure writes. The VM reads all of them with its own
# identity, which gets Key Vault Secrets User on each entry and nothing else.
# It also lets the load balancer's IP through the Postgres firewall.
#
# With the private CA, clients dial the IP (or dns_name) and check the
# certificate against temporal.autoheal.internal, so no DNS record is needed.
# With certificate_name, the vault certificate must cover dns_name, and a DNS
# record for dns_name must point at the temporal_ip output. The outputs feed
# compositions/azure-runner and the app's chart values.
#
# start_temporal is false by default: the VM comes up with the gate only. The
# cutover starts Temporal with az vmss run-command, then sets start_temporal
# to true so a reimage keeps it on. See the README.

locals {
  # null-label id, e.g. acme-prod-autoheal. Resources add a -temporal suffix.
  id = lower(join("-", compact([var.namespace, var.environment, var.name])))

  # The name in the private CA's certificate.
  internal_name = "temporal.autoheal.internal"

  # The name clients check in the gate's certificate.
  server_name = var.dns_name != "" ? var.dns_name : local.internal_name

  private_ca = var.certificate_name == ""

  # The vault entries this composition writes with the private CA.
  certificate_secret_name = local.private_ca ? "temporal-tls" : var.certificate_name
  ca_secret_name          = "temporal-ca"

  # The vault name is the last element of its resource ID. The URI assumes the
  # Azure public cloud, as the rest of the repo does.
  key_vault_uri = "https://${split("/", var.key_vault_id)[8]}.vault.azure.net/"

  # Each entry the VM reads, keyed by a fixed label so the keys are known in
  # the plan.
  vm_secrets = merge(
    {
      api_server_key = var.api_server_key_secret_name
      agents_key     = var.agents_key_secret_name
      runner_key     = var.runner_key_secret_name
      certificate    = local.certificate_secret_name
    },
    local.private_ca ? { ca = local.ca_secret_name } : {},
  )

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
    precondition {
      condition     = local.private_ca || var.dns_name != ""
      error_message = "certificate_name needs dns_name: clients dial dns_name and check it in the vault certificate."
    }
    precondition {
      condition     = length(distinct(values(local.vm_secrets))) == length(local.vm_secrets)
      error_message = "The vault entries for the two app keys, the runner key and the certificate must all differ (temporal-tls and temporal-ca are taken with the private CA)."
    }
  }
}

# --- Keys -------------------------------------------------------------------

# One key per app client, sent as "Bearer <key>". The gate lets an app key
# call all of WorkflowService except the few calls it refuses for every key.
# Letters and digits only, so they are safe in env files.
#
# Terraform makes the first version only. To rotate, add a new version in the
# vault (az keyvault secret set). The gate accepts the two newest enabled
# versions, so clients move over, and then the old version is disabled. The
# apply keeps its hands off the value after the first one.
resource "random_password" "api_server_key" {
  length  = 64
  special = false
}

resource "random_password" "agents_key" {
  length  = 64
  special = false
}

resource "azurerm_key_vault_secret" "api_server_key" {
  name         = var.api_server_key_secret_name
  value        = random_password.api_server_key.result
  key_vault_id = var.key_vault_id
  content_type = "text/plain"
  tags         = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_key_vault_secret" "agents_key" {
  name         = var.agents_key_secret_name
  value        = random_password.agents_key.result
  key_vault_id = var.key_vault_id
  content_type = "text/plain"
  tags         = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}

# --- Private CA and certificate (without certificate_name) -------------------

# A private CA for the gate's certificate. Clients trust it through the
# temporal_ca_certificate output or the vault entry temporal-ca. Renewing it
# (in its last year) means the app and the runner must take the new CA, so it
# lasts 10 years.
resource "tls_private_key" "ca" {
  count       = local.private_ca ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "ca" {
  count           = local.private_ca ? 1 : 0
  private_key_pem = tls_private_key.ca[0].private_key_pem

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
  count       = local.private_ca ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "server" {
  count           = local.private_ca ? 1 : 0
  private_key_pem = tls_private_key.server[0].private_key_pem
  dns_names       = distinct(compact([local.internal_name, var.dns_name]))

  subject {
    common_name  = local.internal_name
    organization = "Autoheal"
  }
}

# Two years. The first apply in its last 90 days makes a new one and writes it
# as a new version of the vault entry. The gate picks it up within 5 minutes,
# with no reimage. Clients need nothing: the CA stays.
resource "tls_locally_signed_cert" "server" {
  count              = local.private_ca ? 1 : 0
  cert_request_pem   = tls_cert_request.server[0].cert_request_pem
  ca_private_key_pem = tls_private_key.ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca[0].cert_pem

  set_subject_key_id    = true
  validity_period_hours = 17520
  early_renewal_hours   = 2160
  allowed_uses          = ["digital_signature", "server_auth"]
}

# The certificate and its private key in one PEM entry, the form the gate
# reads.
resource "azurerm_key_vault_secret" "certificate" {
  count        = local.private_ca ? 1 : 0
  name         = local.certificate_secret_name
  value        = "${tls_locally_signed_cert.server[0].cert_pem}${tls_private_key.server[0].private_key_pem}"
  key_vault_id = var.key_vault_id
  content_type = "application/x-pem-file"
  tags         = var.tags
}

# The CA, for the app's chart values to read. Not a secret.
resource "azurerm_key_vault_secret" "ca" {
  count        = local.private_ca ? 1 : 0
  name         = local.ca_secret_name
  value        = tls_self_signed_cert.ca[0].cert_pem
  key_vault_id = var.key_vault_id
  content_type = "application/x-pem-file"
  tags         = var.tags
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

  key_vault_uri              = local.key_vault_uri
  api_server_key_secret_name = var.api_server_key_secret_name
  agents_key_secret_name     = var.agents_key_secret_name
  runner_key_secret_name     = var.runner_key_secret_name
  certificate_secret_name    = local.certificate_secret_name
  runner_allowed_methods     = var.runner_allowed_methods

  log_analytics_workspace_id = var.log_analytics_workspace_id
  action_group_ids           = var.action_group_ids

  admin_ssh_public_key = tls_private_key.ssh.public_key_openssh

  depends_on = [terraform_data.validate_inputs]
}

# --- Key Vault access -------------------------------------------------------

# Key Vault Secrets User for the VM's identity on each entry it reads, not on
# the vault. The vault must use Azure RBAC. runner-token and a vault
# certificate must exist before this apply; the role assignment needs them.
# The VM retries until the grants and the vault firewall let it in.
resource "azurerm_role_assignment" "vm_secrets" {
  for_each = local.vm_secrets

  scope                = "${var.key_vault_id}/secrets/${each.value}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.temporal_vm.identity_principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [
    azurerm_key_vault_secret.api_server_key,
    azurerm_key_vault_secret.agents_key,
    azurerm_key_vault_secret.certificate,
    azurerm_key_vault_secret.ca,
  ]
}

# --- Postgres ---------------------------------------------------------------

# Lets the load balancer's IP, the VM's only way out, into the Postgres server.
# The server must take public connections (compositions/azure with a public
# Postgres server); a server reachable only from its VNet has no firewall
# rules.
resource "azurerm_postgresql_flexible_server_firewall_rule" "temporal" {
  name             = "${local.id}-temporal"
  server_id        = var.postgres_server_id
  start_ip_address = module.temporal_vm.public_ip
  end_ip_address   = module.temporal_vm.public_ip
}
