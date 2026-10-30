# Plans of compositions/azure-temporal against mocked providers: names, the
# keys and the certificate, the Postgres firewall rule, the vault entries, the
# outputs compositions/azure-runner takes, and the input checks. Nothing here
# reaches Azure. vm.tftest.hcl tests the VM module itself (cloud-init, NSG).
#
# Terraform 1.9 leaves generated values (random, tls) unknown in a plan, so the
# runs check how they are made, not their values. (OpenTofu fills them from the
# mock defaults, which must pass the module's input checks.)

mock_provider "azurerm" {
  # Well-formed IDs where one resource takes another's: OpenTofu fills computed
  # strings at random, and the provider parses these.
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal" }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal-temporal" }
  }
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal-temporal/subnets/snet-temporal" }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/networkSecurityGroups/acme-prod-autoheal-temporal-nsg" }
  }
  mock_resource "azurerm_public_ip" {
    defaults = {
      id         = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/publicIPAddresses/acme-prod-autoheal-temporal-ip"
      ip_address = "198.51.100.7"
    }
  }
  mock_resource "azurerm_network_interface" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/networkInterfaces/acme-prod-autoheal-temporal-nic" }
  }
  mock_resource "azurerm_linux_virtual_machine" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Compute/virtualMachines/acme-prod-autoheal-temporal" }
  }
}

# Values that pass the module's checks. Placeholders, not keys.
mock_provider "tls" {
  mock_resource "tls_private_key" {
    defaults = {
      private_key_pem    = "placeholder"
      public_key_openssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINFlvSQOlsXadV0jY203l2L/29Z+UVVS7GE+uwtP18N1 acme"
    }
  }
  mock_resource "tls_self_signed_cert" {
    defaults = { cert_pem = "-----BEGIN CERTIFICATE-----\nplaceholder\n-----END CERTIFICATE-----\n" }
  }
  mock_resource "tls_locally_signed_cert" {
    defaults = { cert_pem = "-----BEGIN CERTIFICATE-----\nplaceholder\n-----END CERTIFICATE-----\n" }
  }
}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = { result = "pendingpendingpendingpendingpendingpendingpendingpendingpendingp" }
  }
}

variables {
  subscription_id      = "11111111-2222-3333-4444-555555555555"
  location             = "eastus2"
  namespace            = "acme"
  environment          = "prod"
  allowed_source_cidrs = ["198.51.100.20/32", "203.0.113.0/28"]
  runner_token         = "pendingpendingpendingpendingpending"
  postgres_server_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
  postgres_fqdn        = "acme-prod-autoheal-db.postgres.database.azure.com"
  temporal_db_password = "placeholder"
}

# --- Defaults ----------------------------------------------------------------

run "defaults_render" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this[0].name == "rg-acme-prod-autoheal-temporal"
    error_message = "The default resource group must be rg-<namespace>-<environment>-<name>-temporal."
  }
  assert {
    condition     = var.start_temporal == false
    error_message = "start_temporal must default to false."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server_firewall_rule.temporal.name == "acme-prod-autoheal-temporal" && azurerm_postgresql_flexible_server_firewall_rule.temporal.server_id == var.postgres_server_id
    error_message = "The firewall rule must be <id>-temporal on postgres_server_id."
  }
  assert {
    condition     = random_password.app_key.length == 64 && random_password.app_key.special == false
    error_message = "The app key must be 64 letters and digits."
  }
  assert {
    condition     = tls_self_signed_cert.ca.is_ca_certificate && contains(tls_self_signed_cert.ca.allowed_uses, "cert_signing") && tls_self_signed_cert.ca.early_renewal_hours > 0
    error_message = "The CA must be a CA certificate that can sign, renewed early."
  }
  assert {
    condition     = tls_cert_request.server.dns_names == tolist(["temporal.autoheal.internal"])
    error_message = "The server certificate must name temporal.autoheal.internal."
  }
  assert {
    condition     = contains(tls_locally_signed_cert.server.allowed_uses, "server_auth") && tls_locally_signed_cert.server.early_renewal_hours > 0 && tls_locally_signed_cert.server.validity_period_hours < tls_self_signed_cert.ca.validity_period_hours
    error_message = "The server certificate must allow server_auth, renew early and expire before the CA."
  }
  assert {
    condition     = output.temporal_server_name == "temporal.autoheal.internal"
    error_message = "temporal_server_name must be temporal.autoheal.internal."
  }
}

run "existing_resource_group" {
  command = plan

  variables {
    existing_resource_group_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-shared"
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 0
    error_message = "With existing_resource_group_id no resource group is created."
  }
}

# --- Key Vault ---------------------------------------------------------------

run "key_vault_null_creates_no_secrets" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault_secret.app_key) == 0 && length(azurerm_key_vault_secret.ca) == 0
    error_message = "Without key_vault_id no vault entry is written."
  }
}

run "key_vault_set_writes_two_secrets" {
  command = plan

  variables {
    key_vault_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal"
  }

  assert {
    condition     = azurerm_key_vault_secret.app_key[0].name == "temporal-app-key" && azurerm_key_vault_secret.ca[0].name == "temporal-ca"
    error_message = "The vault entries must be temporal-app-key and temporal-ca."
  }
  assert {
    condition     = azurerm_key_vault_secret.app_key[0].key_vault_id == var.key_vault_id && azurerm_key_vault_secret.ca[0].key_vault_id == var.key_vault_id
    error_message = "Both entries must go to key_vault_id."
  }
}

# --- Outputs -----------------------------------------------------------------

# The VM module's outputs are set here so the address is known in the plan.
run "outputs_shape" {
  command = plan

  override_module {
    target = module.temporal_vm
    outputs = {
      public_ip                 = "198.51.100.7"
      vm_id                     = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Compute/virtualMachines/acme-prod-autoheal-temporal"
      vm_name                   = "acme-prod-autoheal-temporal"
      vnet_id                   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal-temporal"
      network_security_group_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/networkSecurityGroups/acme-prod-autoheal-temporal-nsg"
    }
  }

  assert {
    condition     = output.temporal_address == "198.51.100.7:7233" && output.public_ip == "198.51.100.7"
    error_message = "temporal_address must be <public IP>:7233."
  }
  # The checks of compositions/azure-runner's temporal_address and
  # temporal_server_name.
  assert {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?:[0-9]{1,5}$", output.temporal_address))
    error_message = "temporal_address must pass compositions/azure-runner's check."
  }
  assert {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", output.temporal_server_name))
    error_message = "temporal_server_name must pass compositions/azure-runner's check."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server_firewall_rule.temporal.start_ip_address == "198.51.100.7" && azurerm_postgresql_flexible_server_firewall_rule.temporal.end_ip_address == "198.51.100.7"
    error_message = "The firewall rule must let in the VM's public IP only."
  }
}

# --- Input checks ------------------------------------------------------------

run "empty_allowed_source_cidrs_fails" {
  command = plan

  variables {
    allowed_source_cidrs = []
  }

  expect_failures = [var.allowed_source_cidrs]
}

run "open_internet_fails" {
  command = plan

  variables {
    allowed_source_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_source_cidrs]
}

run "host_bits_in_cidr_fail" {
  command = plan

  variables {
    allowed_source_cidrs = ["198.51.100.20/24"]
  }

  expect_failures = [var.allowed_source_cidrs]
}

run "short_runner_token_fails" {
  command = plan

  variables {
    runner_token = "tooshort"
  }

  expect_failures = [var.runner_token]
}

run "postgres_in_other_subscription_fails" {
  command = plan

  variables {
    postgres_server_id = "/subscriptions/99999999-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "bad_key_vault_id_fails" {
  command = plan

  variables {
    key_vault_id = "kv-acme-prod-autoheal"
  }

  expect_failures = [var.key_vault_id]
}
