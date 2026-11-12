# Runs of modules/azure/runner-vmss on its own: the runner VMs' cloud-init.
# Nothing here reaches Azure.
#
# The files in fixtures/ are the cloud-init of the release before temporal_ip,
# rendered from that release's template with the inputs below: one with the
# defaults, one with every option (registry login, private CA, server name,
# tool results, sandbox pre-pull). Without temporal_ip the cloud-init, and so
# the custom data, must match them byte for byte, or every runner VM would be
# reimaged on upgrade. With temporal_ip it must add the runner network and the
# 7233 rule, give the CA to the Temporal client only, and nothing else.
# custom_ca_certificate must add its file, and the CA folder mount when no
# Temporal CA brings it, and nothing else.
#
# The cloud-init takes the identity's client ID, which Terraform 1.9 leaves
# unknown in a plan, so these runs apply against the mocks. It holds the
# runner key, so it is sensitive; the runs read it through nonsensitive(). The
# key here is a placeholder.

mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-runner/providers/Microsoft.ManagedIdentity/userAssignedIdentities/acme-prod-autoheal-runner-uai"
      principal_id = "44444444-4444-4444-4444-444444444444"
      client_id    = "55555555-5555-5555-5555-555555555555"
      tenant_id    = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  namespace   = "acme"
  environment = "prod"
  name        = "autoheal"
  attributes  = ["runner"]

  resource_group_name = "rg-acme-prod-autoheal-runner"
  location            = "eastus2"
  subnet_id           = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal-runner/providers/Microsoft.Network/virtualNetworks/acme-prod-autoheal-runner/subnets/snet-runner"

  temporal_host        = "runner.autoheal.acme.example:443"
  temporal_token       = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ01" # pragma: allowlist secret
  runner_image         = "public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0-rc.12"
  runner_name          = "acme-prod-autoheal-runner"
  admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINFlvSQOlsXadV0jY203l2L/29Z+UVVS7GE+uwtP18N1 acme"
}

# The defaults: public images, Temporal through the edge, no temporal_ip.
run "defaults_match_previous_release" {
  command = apply

  module {
    source = "../../modules/azure/runner-vmss"
  }

  assert {
    condition     = nonsensitive(local.cloud_init) == file("tests/fixtures/cloud-init-default.yaml")
    error_message = "Without temporal_ip the cloud-init must match the previous release byte for byte."
  }

  assert {
    condition     = nonsensitive(azurerm_linux_virtual_machine_scale_set.runner.custom_data) == base64encode(file("tests/fixtures/cloud-init-default.yaml"))
    error_message = "The custom data must stay the base64 of the same cloud-init, with no gzip."
  }
}

# Every option the template has, still without temporal_ip.
run "all_options_match_previous_release" {
  command = apply

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    temporal_host              = "198.51.100.7:7233"
    temporal_server_name       = "temporal.autoheal.internal"
    temporal_ca_certificate    = "-----BEGIN CERTIFICATE-----\nplaceholder-ca\n-----END CERTIFICATE-----\n"
    tool_response_callback_url = "http://10.60.15.253:8083/api/v1/internal/sandbox-tool-responses"
    sandbox_image              = "public.ecr.aws/e4h3h0d9/app/sandbox:chart-1.0.0-rc.12"
    acr_name                   = "cracmeprodautoheal"
  }

  assert {
    condition     = nonsensitive(local.cloud_init) == file("tests/fixtures/cloud-init-all-options.yaml")
    error_message = "Without temporal_ip the cloud-init must match the previous release byte for byte."
  }

  assert {
    condition     = nonsensitive(azurerm_linux_virtual_machine_scale_set.runner.custom_data) == base64encode(file("tests/fixtures/cloud-init-all-options.yaml"))
    error_message = "The custom data must stay the base64 of the same cloud-init, with no gzip."
  }
}

# A Temporal VM: runner-go gets its own network, other containers get a reset
# on 7233 to the VM's IP, and the CA is for the Temporal client only. Taking
# the added lines out and putting the CA lines back gives the previous release
# again.
run "temporal_ip_adds_runner_network_and_rule" {
  command = apply

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    temporal_host              = "198.51.100.7:7233"
    temporal_server_name       = "temporal.autoheal.internal"
    temporal_ca_certificate    = "-----BEGIN CERTIFICATE-----\nplaceholder-ca\n-----END CERTIFICATE-----\n"
    tool_response_callback_url = "http://10.60.15.253:8083/api/v1/internal/sandbox-tool-responses"
    sandbox_image              = "public.ecr.aws/e4h3h0d9/app/sandbox:chart-1.0.0-rc.12"
    acr_name                   = "cracmeprodautoheal"
    temporal_ip                = "198.51.100.7"
  }

  assert {
    condition = [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : [for l in split("\n", f.content) : trimspace(l) if strcontains(l, "iptables")] if f.path == "/usr/local/bin/block-imds.sh"][0] == [
      "iptables -w -C DOCKER-USER -d 169.254.169.254/32 -p tcp -j REJECT --reject-with tcp-reset 2>/dev/null ||",
      "iptables -w -I DOCKER-USER -d 169.254.169.254/32 -p tcp -j REJECT --reject-with tcp-reset",
      "iptables -w -C DOCKER-USER ! -s 172.31.255.240/28 -d 198.51.100.7/32 -p tcp --dport 7233 -j REJECT --reject-with tcp-reset 2>/dev/null ||",
      "iptables -w -I DOCKER-USER ! -s 172.31.255.240/28 -d 198.51.100.7/32 -p tcp --dport 7233 -j REJECT --reject-with tcp-reset",
    ]
    error_message = "block-imds.sh keeps the metadata rule and adds the 7233 rule for every source outside the runner network."
  }

  assert {
    condition = [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : [for l in split("\n", f.content) : l if startswith(l, "ExecStartPre=")] if f.path == "/etc/systemd/system/runner-go.service"][0] == [
      "ExecStartPre=-/usr/bin/docker rm -f runner-go",
      "ExecStartPre=/usr/local/bin/block-imds.sh",
      "ExecStartPre=/bin/sh -c '/usr/bin/docker network inspect runner-go >/dev/null 2>&1 || /usr/bin/docker network create --subnet 172.31.255.240/28 runner-go'",
      "ExecStartPre=/usr/local/bin/runner-pull.sh public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0-rc.12",
    ]
    error_message = "The unit sets the rules, then makes the runner network if it is missing, then pulls the image."
  }

  assert {
    condition     = strcontains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/systemd/system/runner-go.service"][0], "--group-add __DOCKER_GID__ \\\n  --network runner-go \\\n  -v /var/run/docker.sock:/var/run/docker.sock \\\n")
    error_message = "runner-go runs on the runner network."
  }

  assert {
    condition     = strcontains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/opt/runner-go/config.env"][0], "\nTEMPORAL_TLS_CA_FILE=/opt/runner-go/ca/temporal-ca.pem\n")
    error_message = "With the Temporal VM, runner-go gets the CA as TEMPORAL_TLS_CA_FILE, for its Temporal client only."
  }

  assert {
    condition     = !strcontains(nonsensitive(local.cloud_init), "SSL_CERT_DIR")
    error_message = "With the Temporal VM, SSL_CERT_DIR is not set: the rest of runner-go keeps the system roots."
  }

  assert {
    condition     = strcontains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/systemd/system/runner-go.service"][0], "  -v /opt/runner-go/ca:/opt/runner-go/ca:ro \\\n")
    error_message = "The CA folder is mounted read-only into runner-go."
  }

  # The CA lines go back to the previous release's, so the rest must match.
  assert {
    condition = join("\n", [
      for l in split("\n", nonsensitive(local.cloud_init)) : lookup({
        "  # The CA of the Temporal VM's certificate. Only runner-go's Temporal client" = "  # The CA of the Temporal certificate. runner-go reads SSL_CERT_DIR on top of",
        "  # trusts it (TEMPORAL_TLS_CA_FILE); git and HTTPS keep the system roots."    = "  # the system trust store, so public CAs keep working.",
        "      TEMPORAL_TLS_CA_FILE=/opt/runner-go/ca/temporal-ca.pem"                  = "      SSL_CERT_DIR=/opt/runner-go/ca",
      }, l, l)
      if !(strcontains(l, "172.31.255.240/28") || strcontains(l, "--network runner-go") || contains([
        "      # the Temporal VM on TCP 7233. Any other container, a sandbox included,",
        "      # gets a reset. The gate on the VM checks the key too.",
        "      # runner-go's own network, the only source block-imds.sh lets reach the",
        "      # Temporal VM. Sandboxes stay on the default bridge: runner-go drives them",
        "      # through the Docker socket, not over the network.",
      ], l))
    ]) == file("tests/fixtures/cloud-init-all-options.yaml")
    error_message = "temporal_ip adds the runner network and the 7233 rule, moves the CA to TEMPORAL_TLS_CA_FILE, and changes nothing else."
  }
}

# Every option and the custom CAs: the file is the only addition, the CA folder
# is mounted once, and no environment variable is set.
run "custom_ca_adds_its_file" {
  command = apply

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    temporal_host              = "198.51.100.7:7233"
    temporal_server_name       = "temporal.autoheal.internal"
    temporal_ca_certificate    = "-----BEGIN CERTIFICATE-----\nplaceholder-ca\n-----END CERTIFICATE-----\n"
    custom_ca_certificate      = "-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca-1\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca-2\n-----END CERTIFICATE-----\n"
    tool_response_callback_url = "http://10.60.15.253:8083/api/v1/internal/sandbox-tool-responses"
    sandbox_image              = "public.ecr.aws/e4h3h0d9/app/sandbox:chart-1.0.0-rc.12"
    acr_name                   = "cracmeprodautoheal"
  }

  assert {
    condition = [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f if f.path == "/opt/runner-go/ca/custom-ca.pem"] == [{
      path        = "/opt/runner-go/ca/custom-ca.pem"
      permissions = "0644"
      content     = "-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca-1\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca-2\n-----END CERTIFICATE-----\n"
    }]
    error_message = "The custom CAs go to /opt/runner-go/ca/custom-ca.pem, 0644, as given."
  }

  assert {
    condition     = replace(nonsensitive(local.cloud_init), "  # The customer's private root CAs. runner-go reads this path by default and\n  # mounts them, on top of its public roots, into every sandbox it creates.\n  - path: /opt/runner-go/ca/custom-ca.pem\n    permissions: '0644'\n    content: |\n      -----BEGIN CERTIFICATE-----\n      placeholder-custom-ca-1\n      -----END CERTIFICATE-----\n      -----BEGIN CERTIFICATE-----\n      placeholder-custom-ca-2\n      -----END CERTIFICATE-----\n", "") == file("tests/fixtures/cloud-init-all-options.yaml")
    error_message = "custom_ca_certificate adds its file and changes nothing else: one CA folder mount, no environment variable."
  }
}

# The custom CAs alone: the file, and the CA folder mount the Temporal CA
# would otherwise bring. SSL_CERT_DIR and TEMPORAL_TLS_CA_FILE stay unset.
run "custom_ca_alone_mounts_the_ca_folder" {
  command = apply

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    custom_ca_certificate = "-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca\n-----END CERTIFICATE-----\n"
  }

  assert {
    condition     = strcontains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/systemd/system/runner-go.service"][0], "  -v /opt/runner-go/ca:/opt/runner-go/ca:ro \\\n")
    error_message = "The CA folder is mounted read-only into runner-go."
  }

  assert {
    condition = replace(replace(nonsensitive(local.cloud_init),
      "  # The customer's private root CAs. runner-go reads this path by default and\n  # mounts them, on top of its public roots, into every sandbox it creates.\n  - path: /opt/runner-go/ca/custom-ca.pem\n    permissions: '0644'\n    content: |\n      -----BEGIN CERTIFICATE-----\n      placeholder-custom-ca\n      -----END CERTIFICATE-----\n", ""),
    "        -v /opt/runner-go/ca:/opt/runner-go/ca:ro \\\n", "") == file("tests/fixtures/cloud-init-default.yaml")
    error_message = "custom_ca_certificate alone adds its file and the CA folder mount, and nothing else."
  }
}

# A Temporal VM and the custom CAs: the folder holds both files, but only
# custom-ca.pem is for every call. The Temporal CA stays with the Temporal
# client, SSL_CERT_DIR stays unset, and the folder is mounted once.
run "custom_ca_with_temporal_ip" {
  command = apply

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    temporal_host           = "198.51.100.7:7233"
    temporal_server_name    = "temporal.autoheal.internal"
    temporal_ca_certificate = "-----BEGIN CERTIFICATE-----\nplaceholder-ca\n-----END CERTIFICATE-----\n"
    custom_ca_certificate   = "-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca\n-----END CERTIFICATE-----\n"
    temporal_ip             = "198.51.100.7"
  }

  assert {
    condition = { for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.path => f.content if startswith(f.path, "/opt/runner-go/ca/") } == {
      "/opt/runner-go/ca/temporal-ca.pem" = "-----BEGIN CERTIFICATE-----\nplaceholder-ca\n-----END CERTIFICATE-----\n"
      "/opt/runner-go/ca/custom-ca.pem"   = "-----BEGIN CERTIFICATE-----\nplaceholder-custom-ca\n-----END CERTIFICATE-----\n"
    }
    error_message = "The CA folder holds the Temporal CA and the custom CAs, each in its own file."
  }

  assert {
    condition     = strcontains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/opt/runner-go/config.env"][0], "\nTEMPORAL_TLS_CA_FILE=/opt/runner-go/ca/temporal-ca.pem\n") && !strcontains(nonsensitive(local.cloud_init), "SSL_CERT_DIR")
    error_message = "The Temporal CA stays with the Temporal client only, and SSL_CERT_DIR stays unset."
  }

  assert {
    condition     = length(regexall("-v /opt/runner-go/ca:/opt/runner-go/ca:ro", nonsensitive(local.cloud_init))) == 1
    error_message = "The CA folder is mounted once."
  }
}

# Tool results through the edge: the callback key is one more line in the
# root-only config.env, next to the URL, and nothing else changes.
run "callback_token_adds_its_line" {
  command = apply

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    temporal_host              = "198.51.100.7:7233"
    temporal_server_name       = "temporal.autoheal.internal"
    temporal_ca_certificate    = "-----BEGIN CERTIFICATE-----\nplaceholder-ca\n-----END CERTIFICATE-----\n"
    tool_response_callback_url = "https://autoheal.acme.example/api/v1/internal/sandbox-tool-responses"
    tool_response_token        = "ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210zyxwvutsrqponmlkjihgfedcba98" # pragma: allowlist secret
    sandbox_image              = "public.ecr.aws/e4h3h0d9/app/sandbox:chart-1.0.0-rc.12"
    acr_name                   = "cracmeprodautoheal"
  }

  assert {
    condition     = [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.permissions if f.path == "/opt/runner-go/config.env"] == ["0600"] && strcontains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/opt/runner-go/config.env"][0], "\nSANDBOX_TOOL_RESPONSE_CALLBACK_URL=https://autoheal.acme.example/api/v1/internal/sandbox-tool-responses\nSANDBOX_TOOL_RESPONSE_CALLBACK_TOKEN=ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210zyxwvutsrqponmlkjihgfedcba98\n") # pragma: allowlist secret
    error_message = "The callback key goes to the root-only config.env as SANDBOX_TOOL_RESPONSE_CALLBACK_TOKEN, after the URL."
  }

  assert {
    condition = replace(nonsensitive(local.cloud_init),
      "      SANDBOX_TOOL_RESPONSE_CALLBACK_URL=https://autoheal.acme.example/api/v1/internal/sandbox-tool-responses\n      SANDBOX_TOOL_RESPONSE_CALLBACK_TOKEN=ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210zyxwvutsrqponmlkjihgfedcba98\n", # pragma: allowlist secret
    "      SANDBOX_TOOL_RESPONSE_CALLBACK_URL=http://10.60.15.253:8083/api/v1/internal/sandbox-tool-responses\n") == file("tests/fixtures/cloud-init-all-options.yaml")
    error_message = "tool_response_token adds its line and changes nothing else."
  }
}

# Another range for the runner network.
run "custom_runner_network" {
  command = apply

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    temporal_host       = "temporal.acme.example:7233"
    temporal_ip         = "198.51.100.7"
    runner_network_cidr = "10.255.255.0/28"
  }

  assert {
    condition     = strcontains(nonsensitive(local.cloud_init), "iptables -w -I DOCKER-USER ! -s 10.255.255.0/28 -d 198.51.100.7/32 -p tcp --dport 7233 -j REJECT --reject-with tcp-reset\n")
    error_message = "The 7233 rule lets only runner_network_cidr through."
  }

  assert {
    condition     = strcontains(nonsensitive(local.cloud_init), "/usr/bin/docker network create --subnet 10.255.255.0/28 runner-go'\n")
    error_message = "The runner network takes runner_network_cidr."
  }
}

run "temporal_ip_must_be_ipv4" {
  command = plan

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    temporal_ip = "2001:db8::7"
  }

  expect_failures = [var.temporal_ip]
}

run "temporal_ip_must_be_an_address" {
  command = plan

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    temporal_ip = "198.51.100.7/32"
  }

  expect_failures = [var.temporal_ip]
}

run "runner_network_without_host_bits" {
  command = plan

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    runner_network_cidr = "172.31.255.241/28"
  }

  expect_failures = [var.runner_network_cidr]
}

run "custom_ca_refuses_a_private_key" {
  command = plan

  module {
    source = "../../modules/azure/runner-vmss"
  }

  variables {
    custom_ca_certificate = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n"
  }

  expect_failures = [var.custom_ca_certificate]
}
