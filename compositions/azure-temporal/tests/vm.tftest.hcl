# Runs of modules/azure/temporal-vm on its own, with plain inputs: the scale
# set (one VM, no public IP, in the load balancer's pool), the NSG, the load
# balancer, the cloud-init with start_temporal off and on, the gate's config,
# logs and the alert, and the input checks. Nothing here reaches Azure.
#
# The cloud-init takes the identity's client ID, which Terraform 1.9 leaves
# unknown in a plan, so the runs that read it apply against the mocks. It holds
# the database password, so it is sensitive; the runs read it through
# nonsensitive(). The password here is a placeholder.

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

  postgres_fqdn           = "acme-prod-autoheal-db.postgres.database.azure.com"
  temporal_db_password    = "placeholder-db-password"
  key_vault_uri           = "https://kv-acme-prod-autoheal.vault.azure.net/"
  certificate_secret_name = "temporal-tls"
  admin_ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINFlvSQOlsXadV0jY203l2L/29Z+UVVS7GE+uwtP18N1 acme"
}

# --- Scale set ---------------------------------------------------------------

run "scale_set_runs_one_vm_without_public_ip" {
  command = apply

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.temporal.instances == 1
    error_message = "The scale set must have exactly one instance."
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.temporal.overprovision == false
    error_message = "Overprovisioning must be off, or Azure may run two Temporal VMs at once."
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.temporal.upgrade_mode == "Manual"
    error_message = "The upgrade mode must be Manual, so the VM changes only when the operator reimages it."
  }
  assert {
    condition = alltrue([
      for nic in azurerm_linux_virtual_machine_scale_set.temporal.network_interface : alltrue([
        for ip in nic.ip_configuration : length(ip.public_ip_address) == 0
      ])
    ])
    error_message = "The VM must have no public IP of its own."
  }
  assert {
    condition     = toset(azurerm_linux_virtual_machine_scale_set.temporal.network_interface[0].ip_configuration[0].load_balancer_backend_address_pool_ids) == toset([azurerm_lb_backend_address_pool.temporal.id])
    error_message = "The VM must be in the load balancer's pool."
  }
  assert {
    condition     = toset(azurerm_linux_virtual_machine_scale_set.temporal.identity[0].identity_ids) == toset([azurerm_user_assigned_identity.temporal.id])
    error_message = "The VM must carry the user-assigned identity."
  }
  assert {
    condition     = azurerm_linux_virtual_machine_scale_set.temporal.disable_password_authentication
    error_message = "Password login must be off."
  }
}

# --- NSG ---------------------------------------------------------------------

run "nsg_allows_7233_and_the_probe_only" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = length(azurerm_network_security_group.temporal.security_rule) == 3
    error_message = "The NSG must have three rules: 7233 from the allowed ranges, the load balancer, deny all."
  }
  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.temporal.security_rule : (
        r.access == "Allow" && r.direction == "Inbound" && r.protocol == "Tcp" && r.destination_port_range == "7233" &&
        toset(r.source_address_prefixes) == toset(["198.51.100.20/32", "203.0.113.0/28"])
      )
    ])
    error_message = "One rule must allow inbound TCP 7233 from allowed_source_cidrs only."
  }
  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.temporal.security_rule : (
        r.access == "Allow" && r.direction == "Inbound" && r.protocol == "Tcp" && r.source_address_prefix == "AzureLoadBalancer" &&
        toset(r.destination_port_ranges) == toset(["7233", "8080"])
      )
    ])
    error_message = "One rule must allow AzureLoadBalancer on 7233 and the health port only."
  }
  assert {
    condition = alltrue([
      for r in azurerm_network_security_group.temporal.security_rule : (
        r.destination_port_range == "7233" || toset(r.destination_port_ranges) == toset(["7233", "8080"])
      ) if r.access == "Allow"
    ])
    error_message = "No allow rule may open another port."
  }
  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.temporal.security_rule : (
        r.access == "Deny" && r.direction == "Inbound" && r.protocol == "*" && r.source_address_prefix == "*" &&
        r.destination_port_range == "*" && r.priority == 4096
      )
    ])
    error_message = "The NSG must deny all other inbound traffic at priority 4096, which overrides Azure's default allow rules."
  }
}

# --- Load balancer -----------------------------------------------------------

run "load_balancer" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = azurerm_public_ip.temporal.allocation_method == "Static" && azurerm_public_ip.temporal.sku == "Standard" && azurerm_lb.temporal.sku == "Standard"
    error_message = "The load balancer and its IP must be Standard, and the IP static."
  }
  assert {
    condition     = azurerm_lb_rule.temporal.frontend_port == 7233 && azurerm_lb_rule.temporal.backend_port == 7233 && azurerm_lb_rule.temporal.protocol == "Tcp"
    error_message = "The load balancer must forward TCP 7233 to 7233."
  }
  assert {
    condition     = azurerm_lb_rule.temporal.disable_outbound_snat == true
    error_message = "The 7233 rule must not give outbound SNAT: the outbound rule does."
  }
  assert {
    condition     = azurerm_lb_outbound_rule.temporal.protocol == "All" && azurerm_lb_outbound_rule.temporal.frontend_ip_configuration[0].name == "public"
    error_message = "An outbound rule on the public frontend must give the VM its way out."
  }
  assert {
    condition     = azurerm_lb_probe.health.protocol == "Http" && azurerm_lb_probe.health.port == 8080 && azurerm_lb_probe.health.request_path == "/healthz"
    error_message = "The probe must be HTTP on the health port at /healthz."
  }
}

# --- cloud-init --------------------------------------------------------------

run "start_temporal_false_leaves_server_off" {
  command = apply

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
    condition     = contains(yamldecode(nonsensitive(local.cloud_init)).runcmd, "systemctl enable temporal-edge.service") && contains(yamldecode(nonsensitive(local.cloud_init)).runcmd, "systemctl enable --now temporal-secrets.timer")
    error_message = "The gate and the key refresh timer must be enabled whatever start_temporal is."
  }
  assert {
    condition     = azurerm_monitor_metric_alert.health.enabled == false
    error_message = "The health alert must be off while Temporal is off."
  }
}

run "start_temporal_true_enables_server" {
  command = apply

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
  assert {
    condition     = azurerm_monitor_metric_alert.health.enabled == true
    error_message = "The health alert must be on with start_temporal."
  }
}

run "files_and_guard" {
  command = apply

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = strcontains(nonsensitive(local.cloud_init), "connectAddr: \"acme-prod-autoheal-db.postgres.database.azure.com:5432\"")
    error_message = "Temporal must connect to postgres_fqdn on 5432."
  }
  assert {
    condition     = [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.permissions if f.path == "/etc/temporal/temporal.env"] == ["0600"]
    error_message = "The env file holds the database password and must be 0600."
  }
  # The password is in temporal.env only. The gate's files hold no secret.
  assert {
    condition = alltrue([
      for f in yamldecode(nonsensitive(local.cloud_init)).write_files : !strcontains(f.content, "placeholder-db-password")
      if f.path != "/etc/temporal/temporal.env"
    ])
    error_message = "The database password must be in /etc/temporal/temporal.env only."
  }
  assert {
    condition = [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/edge.conf"] == [join("", [
      "KEY_VAULT_URI='https://kv-acme-prod-autoheal.vault.azure.net'\n",
      "IDENTITY_CLIENT_ID='66666666-6666-6666-6666-666666666666'\n",
      "API_SERVER_KEY_ENTRY='temporal-api-server-key'\n",
      "AGENTS_KEY_ENTRY='temporal-agents-key'\n",
      "RUNNER_KEY_ENTRY='runner-token'\n",
      "CERTIFICATE_ENTRY='temporal-tls'\n",
    ])]
    error_message = "edge.conf must name the vault without a trailing slash, the identity and the default entries."
  }
  assert {
    condition     = [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : split("\n", trimspace(f.content)) if f.path == "/etc/temporal-edge/runner-methods"][0] == var.runner_allowed_methods
    error_message = "runner-methods must list runner_allowed_methods, one per line."
  }
  assert {
    condition     = contains(var.runner_allowed_methods, "SetWorkerDeploymentCurrentVersion") && !contains(var.runner_allowed_methods, "TerminateWorkflowExecution")
    error_message = "The default runner list must hold SetWorkerDeploymentCurrentVersion and not TerminateWorkflowExecution."
  }
  assert {
    condition     = [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : split("\n", trimspace(f.content)) if f.path == "/etc/temporal-edge/denied-methods"][0] == tolist(["RegisterNamespace", "UpdateNamespace", "DeprecateNamespace", "StartBatchOperation", "DeleteWorkflowExecution", "DeleteWorkerDeployment", "DeleteWorkerDeploymentVersion"])
    error_message = "denied-methods must list the seven calls refused for every key, and not TerminateWorkflowExecution or SetWorkerDeploymentCurrentVersion."
  }
  # The guard runs before the schema step and again just before the start.
  assert {
    condition = [
      for l in split("\n", [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/systemd/system/temporal-server.service"][0]) :
      element(split(" ", trimprefix(l, "ExecStartPre=")), 0) if startswith(l, "ExecStartPre=")
      ] == [
      "-/usr/bin/docker",
      "/usr/local/bin/temporal-pull.sh",
      "/usr/local/bin/temporal-guard.sh",
      "/usr/local/bin/temporal-schema.sh",
      "/usr/local/bin/temporal-guard.sh",
    ]
    error_message = "temporal-server must run the guard before the schema step and again before Temporal starts."
  }
  assert {
    condition     = strcontains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/systemd/system/temporal-edge.service"][0], "ExecStartPre=/usr/local/bin/temporal-secrets.sh --wait")
    error_message = "The gate must wait for the key refresh before it starts."
  }
  assert {
    condition     = strcontains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/systemd/system/temporal-secrets.timer"][0], "OnUnitActiveSec=5min")
    error_message = "The key refresh must run every 5 minutes."
  }
}

# --- Gate --------------------------------------------------------------------

run "gate_config" {
  command = apply

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].transport_socket.typed_config.common_tls_context.tls_params == { tls_minimum_protocol_version = "TLSv1_3", tls_maximum_protocol_version = "TLSv1_3" }
    error_message = "The gate must offer TLS 1.3 only."
  }
  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].transport_socket.typed_config.common_tls_context.tls_certificate_sds_secret_configs[0].sds_config.path_config_source.path == "/var/lib/temporal-edge/cert/cert.json"
    error_message = "The gate must load its certificate from the file temporal-secrets.sh writes."
  }
  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].filters[0].typed_config.rds.config_source.path_config_source.path == "/var/lib/temporal-edge/routes/routes.json"
    error_message = "The gate must load its routes from the file temporal-secrets.sh writes."
  }
  assert {
    condition = !anytrue([
      for v in values(yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[0].filter_chains[0].filters[0].typed_config.access_log[0].typed_config.log_format.json_format) :
      strcontains(lower(v), "authorization")
    ])
    error_message = "The access log must never record the authorization header."
  }
  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[1].address.socket_address.port_value == 8080
    error_message = "The health listener must be on health_port."
  }
  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.listeners[1].filter_chains[0].filters[0].typed_config.http_filters[0].typed_config.cluster_min_healthy_percentages == { temporal = { value = 100 } }
    error_message = "The health listener must answer 200 only while Temporal passes the gate's health check."
  }
  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.clusters[0].health_checks[0].grpc_health_check.service_name == "temporal.api.workflowservice.v1.WorkflowService"
    error_message = "The gate must check Temporal with the gRPC health check."
  }
  assert {
    condition     = yamldecode([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/envoy.yaml"][0]).static_resources.clusters[0].load_assignment.endpoints[0].lb_endpoints[0].endpoint.address.socket_address == { address = "127.0.0.1", port_value = 17233 }
    error_message = "The gate must reach Temporal on 127.0.0.1:17233."
  }
}

run "custom_runner_methods" {
  command = apply

  module {
    source = "../../modules/azure/temporal-vm"
  }

  variables {
    runner_allowed_methods = ["GetSystemInfo", "PollActivityTaskQueue"]
  }

  assert {
    condition     = [for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.content if f.path == "/etc/temporal-edge/runner-methods"] == ["GetSystemInfo\nPollActivityTaskQueue\n"]
    error_message = "runner-methods must hold the given list."
  }
}

# --- Logs and alert ----------------------------------------------------------

run "logs_off_by_default" {
  command = apply

  module {
    source = "../../modules/azure/temporal-vm"
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.temporal) == 0 && length(azurerm_monitor_data_collection_rule_association.temporal) == 0
    error_message = "Without a workspace there is no data collection rule."
  }
  assert {
    condition     = length(azurerm_linux_virtual_machine_scale_set.temporal.extension) == 0
    error_message = "Without a workspace the VM gets no Azure Monitor agent."
  }
  assert {
    condition     = !contains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.path], "/etc/systemd/journald.conf.d/50-forward-to-syslog.conf")
    error_message = "Without a workspace journald is left as it is."
  }
  assert {
    condition     = length(azurerm_monitor_metric_alert.health.action) == 0
    error_message = "Without action groups the alert notifies no one."
  }
  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.certificate) == 0
    error_message = "Without a workspace there is no certificate alert."
  }
}

run "logs_and_alert_actions" {
  command = apply

  module {
    source = "../../modules/azure/temporal-vm"
  }

  variables {
    log_analytics_workspace_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-ops/providers/Microsoft.OperationalInsights/workspaces/law-acme-ops"
    action_group_ids           = ["/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-ops/providers/Microsoft.Insights/actionGroups/ag-acme-ops"]
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.temporal) == 1 && azurerm_monitor_data_collection_rule.temporal[0].destinations[0].log_analytics[0].workspace_resource_id == var.log_analytics_workspace_id
    error_message = "With a workspace a data collection rule must send to it."
  }
  assert {
    condition     = azurerm_monitor_data_collection_rule_association.temporal[0].target_resource_id == azurerm_linux_virtual_machine_scale_set.temporal.id
    error_message = "The data collection rule must be associated with the scale set."
  }
  assert {
    condition     = [for e in azurerm_linux_virtual_machine_scale_set.temporal.extension : e.type] == ["AzureMonitorLinuxAgent"]
    error_message = "With a workspace the VM must get the Azure Monitor agent."
  }
  assert {
    condition     = jsondecode([for e in azurerm_linux_virtual_machine_scale_set.temporal.extension : e.settings][0]).authentication.managedIdentity["identifier-value"] == azurerm_user_assigned_identity.temporal.id
    error_message = "The agent must sign in with the VM's identity."
  }
  assert {
    condition     = contains([for f in yamldecode(nonsensitive(local.cloud_init)).write_files : f.path], "/etc/systemd/journald.conf.d/50-forward-to-syslog.conf")
    error_message = "With a workspace journald must forward to syslog."
  }
  assert {
    condition     = azurerm_monitor_metric_alert.health.criteria[0].metric_name == "DipAvailability" && azurerm_monitor_metric_alert.health.criteria[0].threshold == 100 && azurerm_monitor_metric_alert.health.window_size == "PT5M"
    error_message = "The alert must fire on DipAvailability below 100 over 5 minutes."
  }
  assert {
    condition     = toset([for a in azurerm_monitor_metric_alert.health.action : a.action_group_id]) == toset(var.action_group_ids)
    error_message = "The alert must notify the given action groups."
  }
  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.certificate) == 1 && azurerm_monitor_scheduled_query_rules_alert_v2.certificate[0].scopes == tolist([var.log_analytics_workspace_id])
    error_message = "With a workspace the certificate alert must query it."
  }
  assert {
    condition     = strcontains(azurerm_monitor_scheduled_query_rules_alert_v2.certificate[0].criteria[0].query, "ProcessName == \"temporal-secrets\"") && strcontains(azurerm_monitor_scheduled_query_rules_alert_v2.certificate[0].criteria[0].query, "SyslogMessage contains \"warning: the certificate in\"")
    error_message = "The certificate alert must match the key refresh's certificate warnings."
  }
  assert {
    condition     = strcontains(nonsensitive(local.cloud_init), "echo \"warning: the certificate in $CERTIFICATE_ENTRY expires within 30 days\"") && strcontains(nonsensitive(local.cloud_init), "echo \"warning: the certificate in $CERTIFICATE_ENTRY has expired\"")
    error_message = "The key refresh must still log the lines the certificate alert matches."
  }
  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.certificate[0].auto_mitigation_enabled && azurerm_monitor_scheduled_query_rules_alert_v2.certificate[0].action[0].action_groups == tolist(var.action_group_ids)
    error_message = "The certificate alert must notify the given action groups once and resolve itself."
  }
}

# --- Input checks ------------------------------------------------------------

run "runner_list_with_a_denied_call_fails" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  variables {
    runner_allowed_methods = ["PollActivityTaskQueue", "DeleteWorkflowExecution"]
  }

  expect_failures = [azurerm_linux_virtual_machine_scale_set.temporal]
}

run "empty_runner_list_fails" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  variables {
    runner_allowed_methods = []
  }

  expect_failures = [var.runner_allowed_methods]
}

run "bad_key_vault_uri_fails" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  variables {
    key_vault_uri = "kv-acme-prod-autoheal"
  }

  expect_failures = [var.key_vault_uri]
}

run "health_port_on_temporal_port_fails" {
  command = plan

  module {
    source = "../../modules/azure/temporal-vm"
  }

  variables {
    health_port = 7233
  }

  expect_failures = [var.health_port]
}
