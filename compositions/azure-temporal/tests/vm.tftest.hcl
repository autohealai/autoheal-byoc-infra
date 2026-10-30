# Plans of modules/azure/temporal-vm on its own, with plain inputs, so the
# cloud-init and the NSG rules are known in the plan: what runs on the VM with
# start_temporal off and on, the proxy's routes, and what the NSG lets in.
# Nothing here reaches Azure.
#
# The cloud-init holds the keys, so it is sensitive; the runs read it through
# nonsensitive(). The keys here are placeholders.

mock_provider "azurerm" {
  # Well-formed IDs where one resource takes another's: OpenTofu fills computed
  # strings at random, and the provider parses these.
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
}

variables {
  namespace            = "acme"
  environment          = "prod"
  name                 = "autoheal"
  attributes           = ["temporal"]
  resource_group_name  = "rg-acme-prod-autoheal-temporal"
  location             = "eastus2"
  address_space        = "10.62.0.0/28"
  allowed_source_cidrs = ["198.51.100.20/32", "203.0.113.0/28"]

  temporal_server_image      = "public.ecr.aws/e4h3h0d9/external/temporal-server:1.29.0"
  temporal_admin_tools_image = "public.ecr.aws/e4h3h0d9/external/temporal-admin-tools:1.29.1-tctl-1.18.4-cli-1.5.0"
  proxy_image                = "public.ecr.aws/e4h3h0d9/external/envoy:distroless-v1.35.6"

  postgres_fqdn        = "acme-prod-autoheal-db.postgres.database.azure.com"
  temporal_db_password = "placeholder"
  app_key              = "appkeyappkeyappkeyappkeyappkeyappkey"
  runner_token         = "pendingpendingpendingpendingpending"
  tls_certificate      = "-----BEGIN CERTIFICATE-----\nplaceholder\n-----END CERTIFICATE-----\n"
  tls_private_key      = "placeholder"
  admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINFlvSQOlsXadV0jY203l2L/29Z+UVVS7GE+uwtP18N1 acme"
}

# --- NSG ---------------------------------------------------------------------

run "nsg_allows_only_7233_from_cidrs" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = length([for r in azurerm_network_security_group.temporal.security_rule : r if r.access == "Allow"]) == 1
    error_message = "The NSG must have exactly one allow rule."
  }
  assert {
    condition = alltrue([
      for r in azurerm_network_security_group.temporal.security_rule : (
        r.direction == "Inbound" && r.protocol == "Tcp" && r.destination_port_range == "7233" &&
        toset(r.source_address_prefixes) == toset(["198.51.100.20/32", "203.0.113.0/28"])
      ) if r.access == "Allow"
    ])
    error_message = "The allow rule must be inbound TCP 7233 from allowed_source_cidrs only."
  }
  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.temporal.security_rule : (
        r.direction == "Inbound" && r.protocol == "*" && r.source_address_prefix == "*" &&
        r.destination_port_range == "*" && r.priority == 4096
      ) if r.access == "Deny"
    ])
    error_message = "The NSG must deny all other inbound traffic at priority 4096, which overrides Azure's default allow rules."
  }
  assert {
    condition     = azurerm_linux_virtual_machine.temporal.disable_password_authentication
    error_message = "Password login must be off."
  }
  assert {
    condition     = azurerm_public_ip.temporal.allocation_method == "Static" && azurerm_public_ip.temporal.sku == "Standard"
    error_message = "The public IP must be static, so it survives a VM replacement."
  }
}

# --- cloud-init --------------------------------------------------------------

run "start_temporal_false_leaves_server_disabled" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = contains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.path], "/etc/systemd/system/temporal-server.service")
    error_message = "The temporal-server unit must be installed."
  }
  assert {
    condition     = !anytrue([for c in yamldecode(nonsensitive(local.cloud_init)).runcmd : strcontains(c, "temporal-server")])
    error_message = "With start_temporal false, nothing may enable or start temporal-server."
  }
  assert {
    condition     = contains(yamldecode(nonsensitive(local.cloud_init)).runcmd, "systemctl enable temporal-edge.service")
    error_message = "The proxy must be enabled whatever start_temporal is."
  }
}

run "start_temporal_true_enables_server" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  variables {
    start_temporal = true
  }

  assert {
    condition     = contains(yamldecode(nonsensitive(local.cloud_init)).runcmd, "systemctl enable temporal-server.service temporal-namespaces.service")
    error_message = "With start_temporal true, temporal-server and temporal-namespaces must be enabled."
  }
}

run "temporal_config" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = strcontains(nonsensitive(local.cloud_init), "connectAddr: \"acme-prod-autoheal-db.postgres.database.azure.com:5432\"")
    error_message = "Temporal must connect to postgres_fqdn on 5432."
  }
  assert {
    condition     = strcontains(nonsensitive(local.cloud_init), "numHistoryShards: 512")
    error_message = "numHistoryShards must default to 512."
  }
  assert {
    condition = alltrue([
      for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.permissions == "0600"
      if contains(["/etc/temporal/temporal.env", "/etc/temporal-edge/tls.key", "/etc/temporal-edge/envoy.yaml"], f.path)
    ])
    error_message = "The env file, the TLS key and the proxy config hold secrets and must be 0600."
  }
}

# --- Proxy -------------------------------------------------------------------

run "proxy_routes" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].filters[0].typed_config.route_config.virtual_hosts[0].domains == ["*"]
    error_message = "The proxy must not route on the host: the Python SDK sends temporal.autoheal.internal, Go clients send the IP."
  }
  assert {
    condition     = length(yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].filters[0].typed_config.route_config.virtual_hosts[0].routes) == 6
    error_message = "The proxy must have six routes: app, runner GetSystemInfo, runner worker API, two health checks and the 401."
  }
  # Dial calls GetSystemInfo first, and the Go SDK sends no namespace header on it.
  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].filters[0].typed_config.route_config.virtual_hosts[0].routes[1].match == { path = "/temporal.api.workflowservice.v1.WorkflowService/GetSystemInfo", headers = [{ name = "authorization", string_match = { exact = "Bearer pendingpendingpendingpendingpending" } }] }
    error_message = "Route 2 must let the runner key call GetSystemInfo without a namespace header."
  }
  assert {
    condition     = contains(yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].filters[0].typed_config.route_config.virtual_hosts[0].routes[2].match.headers, { name = "temporal-namespace", string_match = { exact = "runners" } })
    error_message = "Route 3 must hold the runner key to the runners namespace."
  }
  assert {
    condition = alltrue([
      for r in slice(yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].filters[0].typed_config.route_config.virtual_hosts[0].routes, 0, 5) :
      r.request_headers_to_remove == ["authorization"] && r.route.cluster == "temporal" && r.route.timeout == "0s"
    ])
    error_message = "Each passing route must remove the key, go to the temporal cluster and have no timeout."
  }
  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].filters[0].typed_config.route_config.virtual_hosts[0].routes[5].direct_response.status == 401
    error_message = "The last route must answer 401."
  }
  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].transport_socket.typed_config.common_tls_context.tls_params == { tls_minimum_protocol_version = "TLSv1_3", tls_maximum_protocol_version = "TLSv1_3" }
    error_message = "The proxy must offer TLS 1.3 only."
  }
}
