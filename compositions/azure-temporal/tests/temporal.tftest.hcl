# Runs of compositions/azure-temporal against mocked providers: names, the keys
# and their vault entries, the private CA and the vault certificate, the VM's
# role assignments on each entry, the Postgres firewall rule, the outputs
# compositions/azure-runner takes, the values found from infra_values, and the
# input checks. Nothing here reaches Azure. vm.tftest.hcl tests the VM module itself (scale set, NSG, cloud-init);
# ca.tftest.hcl tests the move to a new CA.
#
# Terraform 1.9 leaves generated values (random, tls, the IP) unknown in a
# plan, so the runs that read them apply against the mocks. (OpenTofu fills
# them from the mock defaults, which must pass the module's input checks.)

mock_provider "azurerm" {
  # Well-formed IDs where one resource takes another's: OpenTofu fills computed
  # strings at random, and the provider parses these.
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal" }
  }
  mock_resource "azurerm_key_vault_secret" {
    defaults = {
      id                      = "https://kv-acme-prod-autoheal.vault.azure.net/secrets/placeholder/00000000000000000000000000000000"
      versionless_id          = "https://kv-acme-prod-autoheal.vault.azure.net/secrets/placeholder"
      resource_id             = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/placeholder/versions/00000000000000000000000000000000"
      resource_versionless_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/placeholder"
    }
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
  mock_resource "azurerm_lb" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/loadBalancers/acme-prod-autoheal-temporal-lb" }
  }
  mock_resource "azurerm_lb_backend_address_pool" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/loadBalancers/acme-prod-autoheal-temporal-lb/backendAddressPools/temporal" }
  }
  mock_resource "azurerm_lb_probe" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Network/loadBalancers/acme-prod-autoheal-temporal-lb/probes/health" }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.ManagedIdentity/userAssignedIdentities/acme-prod-autoheal-temporal-uai"
      client_id    = "66666666-6666-6666-6666-666666666666"
      principal_id = "77777777-7777-7777-7777-777777777777"
    }
  }
  mock_resource "azurerm_linux_virtual_machine_scale_set" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Compute/virtualMachineScaleSets/acme-prod-autoheal-temporal" }
  }
  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-temporal/providers/Microsoft.Insights/dataCollectionRules/acme-prod-autoheal-temporal-dcr" }
  }
}

# Values that pass the module's checks. Placeholders, not keys.
mock_provider "tls" {
  mock_resource "tls_private_key" {
    defaults = {
      private_key_pem    = "-----BEGIN PRIVATE KEY-----\nplaceholder\n-----END PRIVATE KEY-----\n" # pragma: allowlist secret
      public_key_openssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINFlvSQOlsXadV0jY203l2L/29Z+UVVS7GE+uwtP18N1 acme"
    }
  }
  mock_resource "tls_self_signed_cert" {
    defaults = {
      cert_pem          = "-----BEGIN CERTIFICATE-----\nplaceholder-ca\n-----END CERTIFICATE-----\n"
      validity_end_time = "2036-01-01T00:00:00Z"
    }
  }
  mock_resource "tls_locally_signed_cert" {
    defaults = { cert_pem = "-----BEGIN CERTIFICATE-----\nplaceholder-server\n-----END CERTIFICATE-----\n" }
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
  postgres_server_id   = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
  postgres_fqdn        = "acme-prod-autoheal-db.postgres.database.azure.com"
  temporal_db_password = "placeholder"
  key_vault_id         = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal"
}

# --- Defaults: private CA ----------------------------------------------------

# An apply, so the runs after it plan against a CA that exists: Terraform 1.9
# cannot read the end date of a CA a plan is about to make, and fails the CA
# expiry check in a plan run.
run "defaults_render" {
  command = apply

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
    condition = alltrue([
      for k in [random_password.api_server_key, random_password.agents_key] : k.length >= 40 && k.special == false
    ])
    error_message = "Each app key must be 40 or more letters and digits."
  }
  assert {
    condition = (
      azurerm_key_vault_secret.api_server_key.name == "temporal-api-server-key" &&
      azurerm_key_vault_secret.agents_key.name == "temporal-agents-key" &&
      azurerm_key_vault_secret.api_server_key.key_vault_id == var.key_vault_id &&
      azurerm_key_vault_secret.agents_key.key_vault_id == var.key_vault_id
    )
    error_message = "The app keys must go to key_vault_id as temporal-api-server-key and temporal-agents-key."
  }
  assert {
    condition     = keys(tls_self_signed_cert.ca) == ["1"] && tls_self_signed_cert.ca["1"].is_ca_certificate && contains(tls_self_signed_cert.ca["1"].allowed_uses, "cert_signing") && tls_self_signed_cert.ca["1"].early_renewal_hours == 0
    error_message = "By default there must be one CA, named 1: a CA certificate that can sign, which no apply renews."
  }
  assert {
    condition     = tls_cert_request.server[0].dns_names == tolist(["temporal.autoheal.internal"])
    error_message = "Without dns_name the server certificate must name temporal.autoheal.internal only."
  }
  assert {
    condition     = contains(tls_locally_signed_cert.server[0].allowed_uses, "server_auth") && tls_locally_signed_cert.server[0].early_renewal_hours > 0 && tls_locally_signed_cert.server[0].validity_period_hours < tls_self_signed_cert.ca["1"].validity_period_hours
    error_message = "The server certificate must allow server_auth, renew early and expire before the CA."
  }
  assert {
    condition = (
      azurerm_key_vault_secret.certificate[0].name == "temporal-tls" && azurerm_key_vault_secret.certificate[0].content_type == "application/x-pem-file" &&
      azurerm_key_vault_secret.ca[0].name == "temporal-ca" && azurerm_key_vault_secret.ca[0].content_type == "application/x-pem-file"
    )
    error_message = "With the private CA the certificate and the CA must go to the vault as PEM entries temporal-tls and temporal-ca."
  }
  assert {
    condition     = output.temporal_server_name == "temporal.autoheal.internal"
    error_message = "Without dns_name temporal_server_name must be temporal.autoheal.internal."
  }
}

# The VM's identity reads each entry it needs and nothing else.
run "role_assignments_private_ca" {
  command = plan

  assert {
    condition = { for k, r in azurerm_role_assignment.vm_secrets : k => r.scope } == {
      api_server_key = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/temporal-api-server-key"
      agents_key     = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/temporal-agents-key"
      runner_key     = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/runner-token"
      certificate    = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/temporal-tls"
      ca             = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/temporal-ca"
    }
    error_message = "The VM must get one role assignment per entry, scoped to that entry: the two app keys, runner-token, temporal-tls and temporal-ca."
  }
  assert {
    condition = alltrue([
      for r in azurerm_role_assignment.vm_secrets : r.role_definition_name == "Key Vault Secrets User" && r.principal_type == "ServicePrincipal"
    ])
    error_message = "Each role assignment must be Key Vault Secrets User for a service principal."
  }
}

run "private_ca_with_dns_name" {
  command = plan

  variables {
    dns_name = "temporal.acme.example.com"
  }

  assert {
    condition     = tls_cert_request.server[0].dns_names == tolist(["temporal.autoheal.internal", "temporal.acme.example.com"])
    error_message = "With dns_name the server certificate must name temporal.autoheal.internal and dns_name."
  }
  assert {
    condition     = output.temporal_server_name == "temporal.acme.example.com" && output.temporal_address == "temporal.acme.example.com:7233"
    error_message = "With dns_name clients must dial and check dns_name."
  }
}

# --- Vault certificate -------------------------------------------------------

run "vault_certificate" {
  command = plan

  variables {
    certificate_name = "temporal-acme"
    dns_name         = "temporal.acme.example.com"
  }

  assert {
    condition = (
      length(tls_private_key.ca) == 0 && length(tls_self_signed_cert.ca) == 0 && length(tls_private_key.server) == 0 &&
      length(tls_cert_request.server) == 0 && length(tls_locally_signed_cert.server) == 0
    )
    error_message = "With certificate_name no CA or certificate is made."
  }
  assert {
    condition     = length(azurerm_key_vault_secret.certificate) == 0 && length(azurerm_key_vault_secret.ca) == 0
    error_message = "With certificate_name the entries temporal-tls and temporal-ca are not written."
  }
  assert {
    condition = { for k, r in azurerm_role_assignment.vm_secrets : k => r.scope } == {
      api_server_key = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/temporal-api-server-key"
      agents_key     = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/temporal-agents-key"
      runner_key     = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/runner-token"
      certificate    = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/temporal-acme"
    }
    error_message = "With certificate_name the VM must read the vault certificate's secret, and no CA entry."
  }
  assert {
    condition     = output.temporal_ca_certificate == null && output.temporal_server_name == "temporal.acme.example.com" && output.temporal_address == "temporal.acme.example.com:7233"
    error_message = "With certificate_name there is no private CA, and clients dial and check dns_name."
  }
}

run "custom_entry_names" {
  command = plan

  variables {
    api_server_key_secret_name = "acme-temporal-api"
    agents_key_secret_name     = "acme-temporal-agents"
    runner_key_secret_name     = "acme-runner"
  }

  assert {
    condition = (
      azurerm_key_vault_secret.api_server_key.name == "acme-temporal-api" && azurerm_key_vault_secret.agents_key.name == "acme-temporal-agents" &&
      endswith(azurerm_role_assignment.vm_secrets["runner_key"].scope, "/secrets/acme-runner")
    )
    error_message = "The entry names must follow the inputs."
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

# --- Values from compositions/azure ------------------------------------------

# With infra_values and none of the four inputs, the vault and the Postgres
# server are found by name and the password is read from the vault. The lookups
# find the IDs the other runs type, so nothing changes.
run "values_from_infra" {
  command = plan

  variables {
    key_vault_id         = ""
    postgres_server_id   = ""
    postgres_fqdn        = ""
    temporal_db_password = ""
    infra_values = {
      global = {
        infra = {
          keyVault = { name = "kv-acme-prod-autoheal" }
          database = { host = "acme-prod-autoheal-db.postgres.database.azure.com" }
        }
      }
    }
  }

  override_data {
    target = data.azurerm_resources.key_vault
    values = {
      resources = [{
        id                  = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal"
        name                = "kv-acme-prod-autoheal"
        type                = "Microsoft.KeyVault/vaults"
        location            = "eastus2"
        resource_group_name = "rg-acme-prod-autoheal"
        tags                = {}
      }]
    }
  }
  override_data {
    target = data.azurerm_resources.postgres
    values = {
      resources = [{
        id                  = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
        name                = "acme-prod-autoheal-db"
        type                = "Microsoft.DBforPostgreSQL/flexibleServers"
        location            = "eastus2"
        resource_group_name = "rg-acme-prod-autoheal"
        tags                = {}
      }]
    }
  }
  override_data {
    target = data.azurerm_key_vault_secret.temporal_db_password
    values = { value = "placeholder-from-the-vault" }
  }

  assert {
    condition     = data.azurerm_resources.key_vault[0].name == "kv-acme-prod-autoheal" && data.azurerm_resources.key_vault[0].type == "Microsoft.KeyVault/vaults"
    error_message = "The vault must be looked up by global.infra.keyVault.name."
  }
  assert {
    condition     = data.azurerm_resources.postgres[0].name == "acme-prod-autoheal-db" && data.azurerm_resources.postgres[0].type == "Microsoft.DBforPostgreSQL/flexibleServers"
    error_message = "The Postgres server must be looked up by the first label of global.infra.database.host."
  }
  assert {
    condition     = data.azurerm_key_vault_secret.temporal_db_password[0].name == "temporal-db-password" && data.azurerm_key_vault_secret.temporal_db_password[0].key_vault_id == "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal"
    error_message = "The password must be read from the entry temporal-db-password in the vault found."
  }
  assert {
    condition     = nonsensitive(local.temporal_db_password) == "placeholder-from-the-vault" && local.postgres_fqdn == "acme-prod-autoheal-db.postgres.database.azure.com"
    error_message = "The VM must get the password from the vault and the host from global.infra.database.host."
  }
  assert {
    condition = (
      azurerm_key_vault_secret.api_server_key.key_vault_id == "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal" &&
      azurerm_key_vault_secret.agents_key.key_vault_id == "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal" &&
      alltrue([for r in azurerm_role_assignment.vm_secrets : startswith(r.scope, "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/kv-acme-prod-autoheal/secrets/")])
    )
    error_message = "The keys and the role assignments must use the vault found."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server_firewall_rule.temporal.server_id == "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
    error_message = "The firewall rule must go on the server found."
  }
}

# An input that is set wins and skips its lookup.
run "inputs_win_over_infra_values" {
  command = plan

  variables {
    infra_values = {
      global = {
        infra = {
          keyVault = { name = "kv-other" }
          database = { host = "other-db.postgres.database.azure.com" }
        }
      }
    }
  }

  assert {
    condition = (
      length(data.azurerm_resources.key_vault) == 0 && length(data.azurerm_resources.postgres) == 0 &&
      length(data.azurerm_key_vault_secret.temporal_db_password) == 0
    )
    error_message = "With the four inputs set nothing is looked up or read."
  }
  assert {
    condition     = local.key_vault_id == var.key_vault_id && local.postgres_server_id == var.postgres_server_id && local.postgres_fqdn == var.postgres_fqdn
    error_message = "The inputs must win over infra_values."
  }
}

# Without infra_values, postgres_fqdn alone finds the server.
run "postgres_server_from_fqdn" {
  command = plan

  variables {
    postgres_server_id = ""
  }

  override_data {
    target = data.azurerm_resources.postgres
    values = {
      resources = [{
        id                  = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
        name                = "acme-prod-autoheal-db"
        type                = "Microsoft.DBforPostgreSQL/flexibleServers"
        location            = "eastus2"
        resource_group_name = "rg-acme-prod-autoheal"
        tags                = {}
      }]
    }
  }

  assert {
    condition     = data.azurerm_resources.postgres[0].name == "acme-prod-autoheal-db" && azurerm_postgresql_flexible_server_firewall_rule.temporal.server_id == "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
    error_message = "postgres_fqdn alone must find the server for the firewall rule."
  }
}

# --- Applied values ----------------------------------------------------------

run "outputs_and_values" {
  command = apply

  assert {
    condition     = output.temporal_address == "198.51.100.7:7233" && output.temporal_ip == "198.51.100.7"
    error_message = "Without dns_name temporal_address must be <load balancer IP>:7233."
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
    condition     = output.temporal_ca_certificate == tls_self_signed_cert.ca["1"].cert_pem && nonsensitive(azurerm_key_vault_secret.ca[0].value) == tls_self_signed_cert.ca["1"].cert_pem
    error_message = "temporal_ca_certificate and the entry temporal-ca must be the private CA."
  }
  assert {
    condition     = nonsensitive(azurerm_key_vault_secret.certificate[0].value) == "${tls_locally_signed_cert.server[0].cert_pem}${nonsensitive(tls_private_key.server[0].private_key_pem)}"
    error_message = "The entry temporal-tls must hold the certificate and then its private key."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server_firewall_rule.temporal.start_ip_address == "198.51.100.7" && azurerm_postgresql_flexible_server_firewall_rule.temporal.end_ip_address == "198.51.100.7"
    error_message = "The firewall rule must let in the load balancer's IP only."
  }
  assert {
    condition     = alltrue([for r in azurerm_role_assignment.vm_secrets : r.principal_id == "77777777-7777-7777-7777-777777777777"])
    error_message = "The role assignments must go to the VM's identity."
  }
  assert {
    condition     = nonsensitive(azurerm_key_vault_secret.api_server_key.value) == nonsensitive(random_password.api_server_key.result)
    error_message = "The first apply must write the generated key."
  }
}

# client_port 443: the address the app and the runner dial carries the port.
# A plan after the applies above, so the load balancer's IP is known.
run "outputs_on_443" {
  command = plan

  variables {
    client_port = 443
  }

  assert {
    condition     = output.temporal_address == "198.51.100.7:443" && output.temporal_ip == "198.51.100.7"
    error_message = "With client_port 443 temporal_address must be <load balancer IP>:443."
  }
  assert {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?:[0-9]{1,5}$", output.temporal_address))
    error_message = "temporal_address must pass compositions/azure-runner's check."
  }
}

run "outputs_on_443_with_dns_name" {
  command = plan

  variables {
    client_port = 443
    dns_name    = "temporal.acme.example.com"
  }

  assert {
    condition     = output.temporal_address == "temporal.acme.example.com:443" && output.temporal_server_name == "temporal.acme.example.com"
    error_message = "With client_port 443 and dns_name, clients must dial dns_name:443 and check dns_name."
  }
}

# The VM calls the vault at the URI the vault reports, in whatever cloud it is.
# The entry is made again, since Terraform 1.9 gives override values only to
# what the run makes.
run "vault_uri_from_the_vault" {
  command = apply

  plan_options {
    replace = [azurerm_key_vault_secret.api_server_key]
  }

  override_resource {
    target = azurerm_key_vault_secret.api_server_key
    values = {
      versionless_id = "https://kv-acme-prod-autoheal.vault.usgovcloudapi.net/secrets/temporal-api-server-key"
    }
  }

  assert {
    condition     = local.key_vault_uri == "https://kv-acme-prod-autoheal.vault.usgovcloudapi.net/"
    error_message = "key_vault_uri must come from the vault's own URI, not a fixed cloud suffix."
  }
}

# A new value from Terraform (here a replaced random_password) must not
# overwrite the key in the vault: keys rotate in the vault, not in Terraform.
run "keys_ignore_new_values" {
  command = apply

  plan_options {
    replace = [random_password.api_server_key, random_password.agents_key]
  }

  override_resource {
    target = random_password.api_server_key
    values = { result = "rotatedrotatedrotatedrotatedrotatedrotatedrotatedrotatedrotatedr" }
  }
  override_resource {
    target = random_password.agents_key
    values = { result = "rotatedrotatedrotatedrotatedrotatedrotatedrotatedrotatedrotatedr" }
  }

  assert {
    condition     = nonsensitive(random_password.api_server_key.result) == "rotatedrotatedrotatedrotatedrotatedrotatedrotatedrotatedrotatedr"
    error_message = "The test must have replaced the generated key."
  }
  assert {
    condition = (
      nonsensitive(azurerm_key_vault_secret.api_server_key.value) == "pendingpendingpendingpendingpendingpendingpendingpendingpendingp" &&
      nonsensitive(azurerm_key_vault_secret.agents_key.value) == "pendingpendingpendingpendingpendingpendingpendingpendingpendingp"
    )
    error_message = "The vault entries must keep their first value (ignore_changes on value)."
  }
}

# --- Input checks ------------------------------------------------------------

run "three_ca_generations_fail" {
  command = plan

  variables {
    ca_generations = ["1", "2", "3"]
  }

  expect_failures = [var.ca_generations]
}

run "repeated_ca_generation_fails" {
  command = plan

  variables {
    ca_generations = ["1", "1"]
  }

  expect_failures = [var.ca_generations]
}

run "bad_ca_generation_name_fails" {
  command = plan

  variables {
    ca_generations = ["CA 2"]
  }

  expect_failures = [var.ca_generations]
}

run "empty_ca_generations_fail" {
  command = plan

  variables {
    ca_generations = []
  }

  expect_failures = [var.ca_generations]
}

run "certificate_name_without_dns_name_fails" {
  command = plan

  variables {
    certificate_name = "temporal-acme"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "entry_name_clash_fails" {
  command = plan

  variables {
    api_server_key_secret_name = "temporal-tls"
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "bad_dns_name_fails" {
  command = plan

  variables {
    dns_name = "198.51.100.7:7233"
  }

  expect_failures = [var.dns_name]
}

run "client_port_zero_fails" {
  command = plan

  variables {
    client_port = 0
  }

  expect_failures = [var.client_port]
}

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

# A vault name in infra_values that is not in subscription_id.
run "vault_not_found_fails" {
  command = plan

  variables {
    key_vault_id = ""
    infra_values = { global = { infra = { keyVault = { name = "kv-acme-prod-autoheal" } } } }
  }

  override_data {
    target = data.azurerm_resources.key_vault
    values = { resources = [] }
  }

  expect_failures = [data.azurerm_resources.key_vault]
}

run "no_vault_fails" {
  command = plan

  variables {
    key_vault_id         = ""
    temporal_db_password = ""
  }

  expect_failures = [terraform_data.validate_inputs, data.azurerm_key_vault_secret.temporal_db_password]
}

run "two_line_password_fails" {
  command = plan

  variables {
    temporal_db_password = "line1\nline2"
  }

  expect_failures = [var.temporal_db_password]
}

# --- CA expiry ---------------------------------------------------------------

# A CA with less than a year left warns. Last, since it leaves an expiring CA
# in the state. CA 2 is new here: Terraform 1.9 gives override values only to
# what the run makes.
run "ca_in_its_last_year_warns" {
  command = apply

  variables {
    ca_generations = ["1", "2"]
  }

  override_resource {
    target = tls_self_signed_cert.ca
    values = { validity_end_time = "2027-01-01T00:00:00Z" }
  }

  expect_failures = [check.ca_expiry]
}
