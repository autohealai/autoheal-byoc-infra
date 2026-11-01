# The move to a new CA, in the steps of the README ("Moving to a new CA"),
# with the real tls provider: each CA and certificate is real, so the runs can
# tell them apart. It works offline. azurerm and random are mocked as in
# temporal.tftest.hcl, and nothing here reaches Azure. The runs share one
# state, in order.

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

run "one_ca" {
  command = apply

  assert {
    condition     = keys(tls_self_signed_cert.ca) == ["1"] && tls_locally_signed_cert.server[0].ca_cert_pem == tls_self_signed_cert.ca["1"].cert_pem
    error_message = "By default CA 1 alone must sign the gate's certificate."
  }
  assert {
    condition     = output.temporal_ca_certificate == tls_self_signed_cert.ca["1"].cert_pem && nonsensitive(azurerm_key_vault_secret.ca[0].value) == output.temporal_ca_certificate
    error_message = "temporal_ca_certificate and the entry temporal-ca must hold CA 1."
  }
  assert {
    condition     = timecmp(tls_self_signed_cert.ca["1"].validity_end_time, timeadd(plantimestamp(), "86400h")) > 0
    error_message = "A new CA must last about 10 years."
  }
}

# Step 1: the new CA is made and trusted; the old one still signs.
run "add_the_new_ca" {
  command = apply

  variables {
    ca_generations = ["1", "2"]
    ca_before      = run.one_ca.temporal_ca_certificate
  }

  assert {
    condition     = keys(tls_self_signed_cert.ca) == ["1", "2"] && tls_self_signed_cert.ca["1"].cert_pem == var.ca_before && tls_self_signed_cert.ca["2"].cert_pem != var.ca_before
    error_message = "ca_generations [1, 2] must keep CA 1 as it was and add a new CA 2."
  }
  assert {
    condition     = output.temporal_ca_certificate == "${tls_self_signed_cert.ca["1"].cert_pem}${tls_self_signed_cert.ca["2"].cert_pem}" && nonsensitive(azurerm_key_vault_secret.ca[0].value) == output.temporal_ca_certificate
    error_message = "temporal_ca_certificate and the entry temporal-ca must hold both CAs, in name order."
  }
  assert {
    condition     = tls_locally_signed_cert.server[0].ca_cert_pem == tls_self_signed_cert.ca["1"].cert_pem
    error_message = "CA 1 must still sign the gate's certificate."
  }
}

# Step 3: the new CA signs a new certificate; what the clients trust does not
# change.
run "move_the_signer" {
  command = apply

  variables {
    ca_generations = ["2", "1"]
    bundle_before  = run.add_the_new_ca.temporal_ca_certificate
  }

  assert {
    condition     = tls_locally_signed_cert.server[0].ca_cert_pem == tls_self_signed_cert.ca["2"].cert_pem
    error_message = "The first CA in ca_generations must sign the gate's certificate."
  }
  assert {
    condition     = nonsensitive(azurerm_key_vault_secret.certificate[0].value) == "${tls_locally_signed_cert.server[0].cert_pem}${nonsensitive(tls_private_key.server[0].private_key_pem)}"
    error_message = "The entry temporal-tls must hold the certificate from CA 2."
  }
  assert {
    condition     = output.temporal_ca_certificate == var.bundle_before && nonsensitive(azurerm_key_vault_secret.ca[0].value) == var.bundle_before
    error_message = "Moving the signer must not change temporal_ca_certificate or the entry temporal-ca."
  }
}

# Step 4: the old CA goes. The gate's certificate stays.
run "drop_the_old_ca" {
  command = apply

  variables {
    ca_generations = ["2"]
    bundle_before  = run.move_the_signer.temporal_ca_certificate
  }

  assert {
    condition     = keys(tls_self_signed_cert.ca) == ["2"] && endswith(var.bundle_before, tls_self_signed_cert.ca["2"].cert_pem)
    error_message = "ca_generations [2] must leave CA 2 alone, as it was."
  }
  assert {
    condition     = tls_locally_signed_cert.server[0].ca_cert_pem == tls_self_signed_cert.ca["2"].cert_pem
    error_message = "CA 2 must sign the gate's certificate."
  }
  assert {
    condition     = output.temporal_ca_certificate == tls_self_signed_cert.ca["2"].cert_pem && nonsensitive(azurerm_key_vault_secret.ca[0].value) == output.temporal_ca_certificate
    error_message = "temporal_ca_certificate and the entry temporal-ca must hold CA 2 alone."
  }
}
