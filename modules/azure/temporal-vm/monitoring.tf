# Logs and the health alert.
#
# With log_analytics_workspace_id, a data collection rule sends the daemon
# syslog facility to the workspace. The gate, the key refresh and Temporal run
# as systemd units, so their output is in the journal, which journald forwards
# to syslog under the unit's name (SyslogIdentifier). Query it with:
#   Syslog | where ProcessName in ("temporal-edge", "temporal-secrets", "temporal-server", "temporal-namespaces")
#
# The health alert watches the load balancer's health probe (DipAvailability).
# It is on only with start_temporal: before the cutover Temporal is off and the
# probe fails on purpose. With the workspace, a log alert also fires while the
# key refresh warns that the gate's certificate expires within 30 days or has
# expired.

resource "azurerm_monitor_data_collection_rule" "temporal" {
  count               = local.logs_enabled ? 1 : 0
  name                = "${module.this.id}-dcr"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  tags                = module.this.tags

  destinations {
    log_analytics {
      name                  = "workspace"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  data_sources {
    syslog {
      name           = "daemon"
      facility_names = ["daemon"]
      log_levels     = ["Debug", "Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
      streams        = ["Microsoft-Syslog"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["workspace"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "temporal" {
  count                   = local.logs_enabled ? 1 : 0
  name                    = "${module.this.id}-dcra"
  target_resource_id      = azurerm_linux_virtual_machine_scale_set.temporal.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.temporal[0].id
}

# Fires when the probe has failed for 5 minutes in a row: Temporal is down, or
# the gate cannot reach it. Maximum below 100 means no sample in the window was
# healthy, so a single restart does not fire it.
resource "azurerm_monitor_metric_alert" "health" {
  name                = "${module.this.id}-health"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_lb.temporal.id]
  description         = "Temporal on ${module.this.id} fails its health check: the load balancer probe on /healthz has failed for 5 minutes."
  severity            = 1
  enabled             = var.start_temporal
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = module.this.tags

  criteria {
    metric_namespace = "Microsoft.Network/loadBalancers"
    metric_name      = "DipAvailability"
    aggregation      = "Maximum"
    operator         = "LessThan"
    threshold        = 100
  }

  dynamic "action" {
    for_each = var.action_group_ids
    content {
      action_group_id = action.value
    }
  }
}

# The key refresh logs "warning: the certificate in <entry> expires within 30
# days" (or "has expired") on each run, every 5 minutes, while it is true. The
# alert is stateful: it notifies once and resolves itself after the next
# certificate is in place. The query is not checked at create time, so a new
# workspace with no Syslog table yet works.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "certificate" {
  count                   = local.logs_enabled ? 1 : 0
  name                    = "${module.this.id}-certificate"
  resource_group_name     = var.resource_group_name
  location                = var.location
  scopes                  = [var.log_analytics_workspace_id]
  description             = "The gate's certificate on ${module.this.id} expires within 30 days or has expired. Put a new version in ${var.certificate_secret_name}; the VM picks it up within 5 minutes."
  severity                = 2
  evaluation_frequency    = "PT1H"
  window_duration         = "PT1H"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  tags                    = module.this.tags

  criteria {
    query                   = <<-KQL
      Syslog
      | where ProcessName == "temporal-secrets"
      | where SyslogMessage contains "warning: the certificate in"
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
  }

  dynamic "action" {
    for_each = length(var.action_group_ids) > 0 ? [1] : []
    content {
      action_groups = var.action_group_ids
    }
  }
}
