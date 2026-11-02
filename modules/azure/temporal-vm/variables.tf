# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The scale set is named from the label id; the VNet, NSG, public IP, load
# balancer and identity add suffixes to it.

variable "resource_group_name" {
  type        = string
  description = "Resource group the VM and its network land in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "address_space" {
  type        = string
  description = "Address range of the VNet, all of it for the subnet snet-temporal. The VNet is connected to nothing, so any private range works."

  validation {
    condition = (
      can(cidrhost(var.address_space, 0)) &&
      try(cidrsubnet(var.address_space, 0, 0) == var.address_space, false) &&
      try(tonumber(split("/", var.address_space)[1]) >= 8 && tonumber(split("/", var.address_space)[1]) <= 29, false)
    )
    error_message = "address_space must be an IPv4 network address with a prefix between /8 and /29, such as 10.62.0.0/28."
  }
}

variable "allowed_source_cidrs" {
  type        = list(string)
  description = "Public ranges allowed to reach the gate on TCP 7233, such as the cluster's outbound addresses and the runner's NAT IP. Nothing else gets in: no SSH, no other port. The load balancer keeps the client's address, so the NSG sees it. The VM's own IP is left out, so a list copied from the install's workload_egress_ip_ranges works."

  validation {
    condition     = length(var.allowed_source_cidrs) > 0
    error_message = "allowed_source_cidrs must list at least one range: with none, nothing can reach Temporal."
  }

  validation {
    condition = alltrue([
      for c in var.allowed_source_cidrs : can(cidrhost(c, 0)) && try(cidrsubnet(c, 0, 0) == c, false) && !startswith(c, "0.0.0.0/")
    ])
    error_message = "Each entry of allowed_source_cidrs must be an IPv4 network address in CIDR form, such as 198.51.100.20/32, and not 0.0.0.0/0."
  }
}

variable "health_port" {
  type        = number
  default     = 8080
  description = "Port of the plain HTTP health listener the load balancer probes at /healthz. Only the AzureLoadBalancer tag may reach it. Not 7233-7235 or 6933-6939, which Temporal and the gate use."

  validation {
    condition = (
      var.health_port >= 1024 && var.health_port <= 65535 && floor(var.health_port) == var.health_port &&
      !contains([7233, 7234, 7235, 9090, 9901, 17233, 17243], var.health_port) &&
      !(var.health_port >= 6933 && var.health_port <= 6939)
    )
    error_message = "health_port must be a whole number from 1024 to 65535 that Temporal and the gate do not use (7233-7235, 6933-6939, 9090, 9901, 17233, 17243)."
  }
}

# ---------------------------------------------------------------------------
# VM
# ---------------------------------------------------------------------------

variable "vm_size" {
  type        = string
  default     = "Standard_D2s_v6"
  description = "VM size. It must support accelerated networking and Premium SSD. 2 vCPU and 8 GiB carry one Temporal server for one install."
}

variable "os_disk_size_gb" {
  type        = number
  default     = 64
  description = "OS disk size in GiB. Temporal keeps its data in Postgres; the disk holds the OS and three images."
}

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = "Admin username on the VM."
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key for the admin user. No password login. The NSG lets no SSH in; use az vmss run-command to reach the host."
}

variable "start_temporal" {
  type        = bool
  default     = false
  description = "Start the Temporal server when the VM is built. False installs it but leaves it off, and only the gate runs. The scale set uses upgrade mode Manual, so a change reaches the VM only when it is reimaged; at cutover the operator starts Temporal with run-command and then sets this to true. Also turns the health alert on."
}

# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

variable "temporal_server_image" {
  type        = string
  description = "Fully qualified Temporal server image, e.g. public.ecr.aws/e4h3h0d9/external/temporal-server:1.29.0."
}

variable "temporal_admin_tools_image" {
  type        = string
  description = "Fully qualified Temporal admin-tools image, for the schema and namespace steps."
}

variable "proxy_image" {
  type        = string
  description = "Fully qualified Envoy image for the gate on 7233, e.g. public.ecr.aws/e4h3h0d9/external/envoy:distroless-v1.35.6."
}

# ---------------------------------------------------------------------------
# Temporal persistence
# ---------------------------------------------------------------------------

variable "postgres_fqdn" {
  type        = string
  description = "Host name of the Postgres server with the temporal and temporal_visibility databases, e.g. acme-prod-autoheal-db.postgres.database.azure.com."

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", var.postgres_fqdn))
    error_message = "postgres_fqdn must be a host name."
  }
}

variable "temporal_db_password" {
  type        = string
  sensitive   = true
  description = "Password of temporal_user. Written to a root-only file on the VM."

  validation {
    condition     = length(var.temporal_db_password) > 0 && !can(regex("[\\r\\n]", var.temporal_db_password))
    error_message = "temporal_db_password must be set and fit on one line."
  }
}

variable "num_history_shards" {
  type        = number
  default     = 512
  description = "numHistoryShards of the Temporal config. It must match the value the database was set up with and can never change after that."
}

# ---------------------------------------------------------------------------
# Keys and certificate, read from Key Vault on the VM
# ---------------------------------------------------------------------------

variable "key_vault_uri" {
  type        = string
  description = "URI of the Key Vault that holds the keys and the certificate, e.g. https://acme-prod-autoheal.vault.azure.net/. The VM reads it with its identity, which needs Key Vault Secrets User on each entry below, and from its public IP, which the vault firewall must let in."

  validation {
    condition     = can(regex("^https://[A-Za-z0-9-]{3,24}\\.vault\\.[A-Za-z0-9.-]+/?$", var.key_vault_uri))
    error_message = "key_vault_uri must be a vault URI such as https://acme-prod-autoheal.vault.azure.net/."
  }
}

variable "api_server_key_secret_name" {
  type        = string
  default     = "temporal-api-server-key"
  description = "Key Vault entry with the api-server-go key. The gate accepts its two newest enabled versions for the app routes."

  validation {
    condition     = can(regex("^[0-9A-Za-z-]{1,127}$", var.api_server_key_secret_name))
    error_message = "api_server_key_secret_name must be a Key Vault secret name: letters, digits and dashes."
  }
}

variable "agents_key_secret_name" {
  type        = string
  default     = "temporal-agents-key"
  description = "Key Vault entry with the agents-py key. The gate accepts its two newest enabled versions for the app routes."

  validation {
    condition     = can(regex("^[0-9A-Za-z-]{1,127}$", var.agents_key_secret_name))
    error_message = "agents_key_secret_name must be a Key Vault secret name: letters, digits and dashes."
  }
}

variable "runner_key_secret_name" {
  type        = string
  default     = "runner-token"
  description = "Key Vault entry with the runner key. The gate accepts its two newest enabled versions for the runner route only."

  validation {
    condition     = can(regex("^[0-9A-Za-z-]{1,127}$", var.runner_key_secret_name))
    error_message = "runner_key_secret_name must be a Key Vault secret name: letters, digits and dashes."
  }
}

variable "certificate_secret_name" {
  type        = string
  description = "Key Vault secret with the gate's certificate, its chain and its private key: the name of a Key Vault certificate (its secret has the same name), or a secret with content type application/x-pem-file. PEM and PKCS#12 (application/x-pkcs12) both work. The gate serves its newest version."

  validation {
    condition     = can(regex("^[0-9A-Za-z-]{1,127}$", var.certificate_secret_name))
    error_message = "certificate_secret_name must be a Key Vault secret name: letters, digits and dashes."
  }
}

variable "runner_allowed_methods" {
  type     = list(string)
  nullable = false
  # The calls runner-go makes with the Temporal Go SDK v1.36 worker: client
  # start, the workflow and activity workers, the sticky cache, worker
  # shutdown, and setting the current version of the sandbox worker
  # deployment. A call missing from the list shows in the gate's access log as
  # a 401 on the route "unauthorized", with the call's path.
  default = [
    "GetSystemInfo",
    "DescribeNamespace",
    "PollWorkflowTaskQueue",
    "PollActivityTaskQueue",
    "RespondWorkflowTaskCompleted",
    "RespondWorkflowTaskFailed",
    "RespondQueryTaskCompleted",
    "RespondActivityTaskCompleted",
    "RespondActivityTaskFailed",
    "RespondActivityTaskCanceled",
    "RecordActivityTaskHeartbeat",
    "GetWorkflowExecutionHistory",
    "ShutdownWorker",
    "SetWorkerDeploymentCurrentVersion",
  ]
  description = "WorkflowService methods the runner key may call, by name. Anything else is 401 for the runner key. Null means the default list."

  validation {
    condition     = length(var.runner_allowed_methods) > 0 && alltrue([for m in var.runner_allowed_methods : can(regex("^[A-Z][A-Za-z]+$", m))])
    error_message = "runner_allowed_methods must list method names such as PollActivityTaskQueue: letters only, starting with a capital."
  }

  # A call the gate refuses for every key (local.denied_methods) is refused by
  # a precondition on the scale set, which reads the one list in main.tf.
}

# ---------------------------------------------------------------------------
# Logs and alert
# ---------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  default     = ""
  description = "Resource ID of a Log Analytics workspace. When set, the VM gets the Azure Monitor agent (signed in with its identity) and a data collection rule that sends the daemon syslog facility, which carries the journal of the gate, the key refresh and Temporal, to the workspace. Empty sends nothing."

  validation {
    condition     = var.log_analytics_workspace_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be empty or the resource ID of a Microsoft.OperationalInsights/workspaces resource."
  }
}

variable "action_group_ids" {
  type        = list(string)
  default     = []
  description = "Resource IDs of action groups the health alert and the certificate alert notify. Empty means the alerts show only in the portal."

  validation {
    condition     = alltrue([for a in var.action_group_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Insights/actionGroups/[^/]+$", a))])
    error_message = "Each entry of action_group_ids must be the resource ID of a Microsoft.Insights/actionGroups resource."
  }
}
