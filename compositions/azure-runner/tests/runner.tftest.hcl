# Plans of compositions/azure-runner against mocked providers: the network we
# create or the subnet we use, the image and registry login, the path to
# Temporal (through the edge, or the runner load balancers), the network
# owner's rules, and the input checks. Nothing here reaches
# Azure. (OpenTofu needs every attribute of a mocked object.)

mock_provider "azurerm" {
  mock_data "azurerm_subnet" {
    defaults = {
      address_prefixes                              = ["10.50.4.0/24"]
      default_outbound_access_enabled               = false
      network_security_group_id                     = ""
      private_endpoint_network_policies             = "Disabled"
      private_link_service_network_policies_enabled = true
      route_table_id                                = ""
      service_endpoints                             = []
    }
  }
  # Well-formed IDs where one resource takes another's: OpenTofu fills computed
  # strings at random, and the provider parses these.
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-runner" }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-runner/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal-runner" }
  }
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-runner/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal-runner/subnets/snet-runner" }
  }
  mock_resource "azurerm_public_ip" {
    defaults = {
      id         = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-runner/providers/Microsoft.Network/publicIPAddresses/acme-prod-autoheal-runner-nat-ip"
      ip_address = "198.51.100.30"
    }
  }
  mock_resource "azurerm_nat_gateway" {
    defaults = { id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-runner/providers/Microsoft.Network/natGateways/acme-prod-autoheal-runner-nat" }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-runner/providers/Microsoft.ManagedIdentity/userAssignedIdentities/acme-prod-autoheal-runner-uai"
      principal_id = "44444444-4444-4444-4444-444444444444"
      client_id    = "55555555-5555-5555-5555-555555555555"
      tenant_id    = "00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "tls" {
  mock_resource "tls_private_key" {
    defaults = { public_key_openssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINFlvSQOlsXadV0jY203l2L/29Z+UVVS7GE+uwtP18N1 acme" }
  }
}

variables {
  subscription_id  = "11111111-2222-3333-4444-555555555555"
  location         = "eastus2"
  namespace        = "acme"
  environment      = "prod"
  temporal_address = "runner.autoheal.acme.example:443"
  temporal_token   = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ01"
  chart_version    = "1.0.0-rc.12"
}

# The defaults: a VNet of our own with snet-runner and a NAT gateway, public
# images, Temporal through the edge with tool results over Temporal, and a
# generated SSH key.
run "creates_network_and_runner" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this[0].name == "rg-acme-prod-autoheal-runner"
    error_message = "The resource group defaults to rg-<namespace>-<environment>-<name>-runner."
  }

  assert {
    condition = (
      azurerm_virtual_network.runner[0].name == "acme-prod-autoheal-runner" &&
      azurerm_virtual_network.runner[0].address_space == toset(["10.61.0.0/24"]) &&
      azurerm_subnet.runner[0].name == "snet-runner" &&
      azurerm_subnet.runner[0].address_prefixes == tolist(["10.61.0.0/24"])
    )
    error_message = "We create a VNet from address_space, all of it for snet-runner."
  }

  assert {
    condition = (
      azurerm_public_ip.runner_nat[0].allocation_method == "Static" &&
      azurerm_public_ip.runner_nat[0].sku == "Standard" &&
      length(azurerm_nat_gateway_public_ip_association.runner) == 1 &&
      length(azurerm_subnet_nat_gateway_association.runner) == 1
    )
    error_message = "The runner subnet gets a NAT gateway with a static public IP."
  }

  assert {
    condition     = module.runner.identity_name == "acme-prod-autoheal-runner-uai"
    error_message = "The runner module is named <id>-runner."
  }

  assert {
    condition     = local.runner_image == "public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0-rc.12" && !local.runner_uses_acr
    error_message = "The runner pulls app/runner-go:chart-<chart_version> from the public registry, with no ACR login."
  }

  assert {
    condition     = local.tool_response_url == ""
    error_message = "Tool results go through Temporal by default."
  }

  assert {
    condition     = length(tls_private_key.runner) == 1
    error_message = "Without admin_ssh_public_key a key pair is generated."
  }

  assert {
    condition     = output.subnet_cidr == "10.61.0.0/24"
    error_message = "subnet_cidr is address_space."
  }

  assert {
    condition = output.required_network_owner_actions == [
      "Give the runner VNet acme-prod-autoheal-runner (10.61.0.0/24, resource group rg-acme-prod-autoheal-runner) a route to runner.autoheal.acme.example: connect it privately to the edge's network, through your hub or a VNet peering, or let it reach a public edge through its NAT gateway.",
      "Allow the runner subnet 10.61.0.0/24, or its NAT gateway's IP over the internet (the egress_ip output), to runner.autoheal.acme.example on TCP 443 (Temporal through the edge).",
      "Point runner.autoheal.acme.example at the edge like the app hostnames: it is the chart's global.edge.runner.host. The edge certificate must cover it, and a shared Istio Gateway must list it in its hosts.",
    ]
    error_message = "The owner routes the VNet to the edge, allows it on 443, and points the runner host at the edge."
  }

  assert {
    condition     = length(output.required_role_assignments) == 0
    error_message = "No grant is listed without a registry."
  }
}

# A subnet the customer already routes to the cluster: no VNet or NAT gateway,
# no egress IP, and the owner's list says what the subnet needs.
run "existing_subnet" {
  command = plan

  variables {
    existing_subnet_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-net/providers/Microsoft.Network/virtualNetworks/vnet-acme-spoke/subnets/snet-autoheal-runner"
  }

  assert {
    condition = (
      length(azurerm_virtual_network.runner) == 0 &&
      length(azurerm_subnet.runner) == 0 &&
      length(azurerm_public_ip.runner_nat) == 0 &&
      length(azurerm_nat_gateway.runner) == 0
    )
    error_message = "With existing_subnet_id no network is created."
  }

  assert {
    condition     = output.egress_ip == null && output.subnet_id == var.existing_subnet_id && output.subnet_cidr == "10.50.4.0/24"
    error_message = "egress_ip is null, and the subnet and its range come from existing_subnet_id."
  }

  assert {
    condition = output.required_network_owner_actions == [
      "Allow the runner subnet 10.50.4.0/24 to runner.autoheal.acme.example on TCP 443 (Temporal through the edge).",
      "Point runner.autoheal.acme.example at the edge like the app hostnames: it is the chart's global.edge.runner.host. The edge certificate must cover it, and a shared Istio Gateway must list it in its hosts.",
      "The runner subnet snet-autoheal-runner uses your routes and no NAT gateway is created: it needs a route to runner.autoheal.acme.example and outbound access to the image registry (public.ecr.aws), the git hosts and the endpoints the tools call.",
    ]
    error_message = "The rule names the brought subnet's range, and a note lists what the subnet needs."
  }
}

# The chart's runner load balancers: a private address, no TLS and no key, and
# the tool-result listener on the same address gets 8083 in the rule.
run "runner_load_balancers" {
  command = plan

  variables {
    temporal_address  = "10.40.15.253:7233"
    temporal_tls      = false
    temporal_token    = ""
    tool_response_url = "http://10.40.15.253:8083/api/v1/internal/sandbox-tool-responses"
  }

  assert {
    condition = output.required_network_owner_actions == [
      "Connect the runner VNet acme-prod-autoheal-runner (10.61.0.0/24, resource group rg-acme-prod-autoheal-runner) privately to the cluster's VNet, through your hub or a VNet peering. Do not publish Temporal on the internet: it has no login, and the traffic carries git tokens and command output.",
      "Allow the runner subnet 10.61.0.0/24 to 10.40.15.253 on TCP 7233 and 8083 (Temporal and sandbox tool results).",
    ]
    error_message = "The owner connects the VNet privately and allows the runner subnet to the address on 7233 and 8083."
  }
}

# A tool_response_url on another host gets its own rule.
run "tool_results_elsewhere" {
  command = plan

  variables {
    temporal_address  = "temporal.acme.internal:7233"
    temporal_tls      = false
    temporal_token    = ""
    tool_response_url = "https://tools.acme.internal/api/v1/internal/sandbox-tool-responses"
  }

  assert {
    condition = output.required_network_owner_actions == [
      "Connect the runner VNet acme-prod-autoheal-runner (10.61.0.0/24, resource group rg-acme-prod-autoheal-runner) privately to the cluster's VNet, through your hub or a VNet peering. Do not publish Temporal on the internet: it has no login, and the traffic carries git tokens and command output.",
      "Allow the runner subnet 10.61.0.0/24 to temporal.acme.internal on TCP 7233 (Temporal).",
      "Allow the runner subnet 10.61.0.0/24 to tools.acme.internal on TCP 443 (sandbox tool results).",
    ]
    error_message = "A host name is accepted, and the tool-result host gets its own rule on the URL's port."
  }
}

# A public edge address is fine through the edge: TLS and the key protect it.
run "public_edge_address" {
  command = plan

  variables {
    temporal_address        = "20.30.40.60:443"
    temporal_server_name    = "runner.autoheal.acme.example"
    temporal_ca_certificate = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"
  }

  assert {
    condition     = output.required_network_owner_actions[1] == "Allow the runner subnet 10.61.0.0/24, or its NAT gateway's IP over the internet (the egress_ip output), to 20.30.40.60 on TCP 443 (Temporal through the edge)."
    error_message = "A public address is accepted with TLS."
  }
}

# The runner image from the customer's ACR: AcrPull for the runner identity and
# a registry login on the VMs. runner_image_tag overrides the tag.
run "image_from_acr" {
  command = plan

  variables {
    acr_id           = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ContainerRegistry/registries/acmeprodautoheal"
    runner_image     = "acmeprodautoheal.azurecr.io/app/runner-go"
    runner_image_tag = "test-1"
  }

  assert {
    condition     = local.runner_image == "acmeprodautoheal.azurecr.io/app/runner-go:test-1" && local.runner_uses_acr && local.acr_name == "acmeprodautoheal"
    error_message = "With the image in acr_id the VMs log in to it; runner_image_tag overrides the tag."
  }

  assert {
    condition     = length(output.required_role_assignments) == 0
    error_message = "The AcrPull grant is created, not listed."
  }
}

# The deployer cannot grant roles: the AcrPull grant is listed instead. A public
# runner image needs no registry login.
run "acr_without_role_assignments" {
  command = plan

  variables {
    acr_id                  = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.ContainerRegistry/registries/acmeprodautoheal"
    create_role_assignments = false
  }

  assert {
    condition     = length(output.required_role_assignments) == 1 && !local.runner_uses_acr
    error_message = "The AcrPull grant is listed, and the public image needs no login."
  }
}

run "brought_resource_group_and_key" {
  command = plan

  variables {
    existing_resource_group_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-runner"
    admin_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINFlvSQOlsXadV0jY203l2L/29Z+UVVS7GE+uwtP18N1 acme"
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 0 && local.rg == "rg-acme-runner" && azurerm_virtual_network.runner[0].resource_group_name == "rg-acme-runner"
    error_message = "With existing_resource_group_id no group is created and the runner goes in it."
  }

  assert {
    condition     = length(tls_private_key.runner) == 0
    error_message = "With admin_ssh_public_key no key pair is generated."
  }
}

# --- Input checks -------------------------------------------------------------

run "temporal_address_needs_a_port" {
  command = plan

  variables {
    temporal_address = "runner.autoheal.acme.example"
  }

  expect_failures = [var.temporal_address]
}

run "temporal_address_port_in_range" {
  command = plan

  variables {
    temporal_address = "runner.autoheal.acme.example:72330"
  }

  expect_failures = [var.temporal_address]
}

# Without TLS Temporal has no key check, so a public address is refused.
run "temporal_address_must_be_private_without_tls" {
  command = plan

  variables {
    temporal_address = "20.30.40.60:7233"
    temporal_tls     = false
    temporal_token   = ""
  }

  expect_failures = [terraform_data.validate_inputs]
}

# The chart's proxy refuses runner calls without the key.
run "tls_needs_the_key" {
  command = plan

  variables {
    temporal_token = ""
  }

  expect_failures = [terraform_data.validate_inputs]
}

# A key over plain gRPC could be read on the way.
run "key_needs_tls" {
  command = plan

  variables {
    temporal_address = "10.40.15.253:7233"
    temporal_tls     = false
  }

  expect_failures = [terraform_data.validate_inputs]
}

run "key_letters_and_digits" {
  command = plan

  variables {
    temporal_token = "short-key"
  }

  expect_failures = [var.temporal_token]
}

run "ca_must_be_pem" {
  command = plan

  variables {
    temporal_ca_certificate = "not a certificate"
  }

  expect_failures = [var.temporal_ca_certificate]
}

run "tool_response_url_must_be_http" {
  command = plan

  variables {
    tool_response_url = "ftp://runner.autoheal.acme.example/results"
  }

  expect_failures = [var.tool_response_url]
}

run "chart_version_must_be_semver" {
  command = plan

  variables {
    chart_version = "v1.0.0"
  }

  expect_failures = [var.chart_version]
}

run "runner_image_without_tag" {
  command = plan

  variables {
    runner_image = "public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0"
  }

  expect_failures = [var.runner_image]
}

run "ids_must_be_resource_ids" {
  command = plan

  variables {
    subscription_id    = "acme-prod"
    acr_id             = "acmeprodautoheal"
    existing_subnet_id = "snet-runner"
  }

  expect_failures = [var.subscription_id, var.acr_id, var.existing_subnet_id]
}

run "address_space_must_be_a_network" {
  command = plan

  variables {
    address_space = "10.61.0.5/24"
  }

  expect_failures = [var.address_space]
}

run "address_space_prefix_in_range" {
  command = plan

  variables {
    address_space = "10.61.0.0/30"
  }

  expect_failures = [var.address_space]
}

# A VM's network interface must be in a subnet of its own subscription.
run "existing_subnet_in_subscription" {
  command = plan

  variables {
    existing_subnet_id = "/subscriptions/66666666-7777-8888-9999-000000000000/resourceGroups/rg-acme-net/providers/Microsoft.Network/virtualNetworks/vnet-acme-hub/subnets/snet-runner"
  }

  expect_failures = [terraform_data.validate_inputs]
}
