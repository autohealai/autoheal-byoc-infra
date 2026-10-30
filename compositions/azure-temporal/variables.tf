# Inputs for the Temporal composition. examples/azure/split-istio/temporal
# shows a typical set. Nothing here reads the cluster.

# ---------------------------------------------------------------------------
# Naming and placement
# ---------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Customer or tenant, e.g. 'acme'. First element of every resource name. Use the namespace of compositions/azure."
}

variable "environment" {
  type        = string
  description = "Lifecycle, e.g. prod, staging, play. Not the region."
}

variable "name" {
  type        = string
  default     = "autoheal"
  description = "Component name; the middle element of resource names. Resources get a -temporal suffix."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto every resource we create."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription for the VM: the subscription of the Postgres server, usually the data subscription of compositions/azure. Get it with: az account show --query id -o tsv"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription GUID. Get it with: az account show --query id -o tsv"
  }
}

variable "location" {
  type        = string
  description = "Azure region, e.g. centralus. The region of the Postgres server keeps Temporal's database calls short."
}

variable "resource_group_name" {
  type        = string
  default     = ""
  description = "Resource group to create for the VM. Empty means 'rg-<namespace>-<environment>-<name>-temporal'. Ignored when existing_resource_group_id is set."
}

variable "existing_resource_group_id" {
  type        = string
  default     = ""
  description = "Resource ID of a resource group in subscription_id to put the VM in, for organizations that do not let the deployer create resource groups. Empty means we create one."

  validation {
    condition     = var.existing_resource_group_id == "" || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.existing_resource_group_id))
    error_message = "existing_resource_group_id must look like /subscriptions/<id>/resourceGroups/<name>."
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "address_space" {
  type        = string
  default     = "10.62.0.0/28"
  description = "Address range of the VM's VNet, all of it for snet-temporal. The VNet is connected to nothing, so any private range works."

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
  description = "Public ranges allowed to reach the VM on TCP 7233: the cluster's outbound addresses (for the app) and the runner's NAT IP (the egress_ip output of compositions/azure-runner). Nothing else gets in."

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

# ---------------------------------------------------------------------------
# Keys and Postgres
# ---------------------------------------------------------------------------

variable "runner_token" {
  type        = string
  sensitive   = true
  description = "The runner key: the runner_token output of compositions/azure, the vault entry runner-token. The proxy lets it into the runners namespace only. Pass the same key to compositions/azure-runner as temporal_token."

  validation {
    condition     = can(regex("^[A-Za-z0-9]{32,}$", var.runner_token))
    error_message = "runner_token must be letters and digits, at least 32 of them: the runner_token output of compositions/azure."
  }
}

variable "postgres_server_id" {
  type        = string
  description = "Resource ID of the install's Postgres flexible server, in subscription_id. We add a firewall rule on it for the VM's public IP."

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.DBforPostgreSQL/flexibleServers/[^/]+$", var.postgres_server_id))
    error_message = "postgres_server_id must be the resource ID of a Microsoft.DBforPostgreSQL/flexibleServers resource."
  }
}

variable "postgres_fqdn" {
  type        = string
  description = "Host name of the same server, e.g. acme-prod-autoheal-db.postgres.database.azure.com: autoheal_values.global.infra.database.host of compositions/azure."

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", var.postgres_fqdn))
    error_message = "postgres_fqdn must be a host name."
  }
}

variable "temporal_db_password" {
  type        = string
  sensitive   = true
  description = "Password of temporal_user, the owner of the temporal and temporal_visibility databases: the vault entry temporal-db-password that compositions/azure writes. Read it with: az keyvault secret show --vault-name <vault> --name temporal-db-password --query value -o tsv"

  validation {
    condition     = length(var.temporal_db_password) > 0 && !can(regex("[\\r\\n]", var.temporal_db_password))
    error_message = "temporal_db_password must be set and fit on one line: the vault entry temporal-db-password."
  }
}

variable "key_vault_id" {
  type        = string
  default     = null
  description = "Resource ID of a Key Vault to write the entries temporal-app-key and temporal-ca to, such as the install vault of compositions/azure. Null writes nothing."

  validation {
    condition     = var.key_vault_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.KeyVault/vaults/[^/]+$", var.key_vault_id))
    error_message = "key_vault_id must be null or the resource ID of a Microsoft.KeyVault/vaults resource."
  }
}

# ---------------------------------------------------------------------------
# VM and images
# ---------------------------------------------------------------------------

variable "start_temporal" {
  type        = bool
  default     = false
  description = "Start the Temporal server on the VM. False leaves it installed but off, and only the proxy runs. Changing it replaces the VM; the public IP stays."
}

variable "vm_size" {
  type        = string
  default     = "Standard_D2s_v6"
  description = "VM size. It must support accelerated networking and Premium SSD. Some policies forbid Intel Dsv5; D2s_v6 is the default for that reason."
}

variable "temporal_server_image" {
  type        = string
  default     = "public.ecr.aws/e4h3h0d9/external/temporal-server:1.29.0"
  description = "Temporal server image, the version the chart runs. For your own registry, copy it there and set the reference here; the VM must be able to pull it without a login."
}

variable "temporal_admin_tools_image" {
  type        = string
  default     = "public.ecr.aws/e4h3h0d9/external/temporal-admin-tools:1.29.1-tctl-1.18.4-cli-1.5.0"
  description = "Temporal admin-tools image, for the schema and namespace steps."
}

variable "proxy_image" {
  type        = string
  default     = "public.ecr.aws/e4h3h0d9/external/envoy:distroless-v1.35.6"
  description = "Envoy image for the proxy on 7233, the one the chart's proxy runs."
}
