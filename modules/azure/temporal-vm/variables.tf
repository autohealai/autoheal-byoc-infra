# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The VM is named from the label id; the VNet, NSG, public IP and NIC add
# suffixes to it.

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
  description = "Public ranges allowed to reach the proxy on TCP 7233, such as the cluster's outbound addresses and the runner's NAT IP. Nothing else gets in: no SSH, no other port."

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
  description = "SSH public key for the admin user. No password login. The NSG lets no SSH in; use az vm run-command to reach the host."
}

variable "start_temporal" {
  type        = bool
  default     = false
  description = "Start the Temporal server. False installs it but leaves it off, and only the proxy runs. Changing it changes the custom data, which replaces the VM; the static public IP stays."
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
  description = "Fully qualified Envoy image for the proxy on 7233, e.g. public.ecr.aws/e4h3h0d9/external/envoy:distroless-v1.35.6."
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
# Proxy keys and certificate
# ---------------------------------------------------------------------------

variable "app_key" {
  type        = string
  sensitive   = true
  description = "Key the app sends as \"Bearer <key>\". It opens the worker API and the health check in every namespace."

  validation {
    condition     = can(regex("^[A-Za-z0-9]{32,}$", var.app_key))
    error_message = "app_key must be letters and digits, at least 32 of them."
  }
}

variable "runner_token" {
  type        = string
  sensitive   = true
  description = "Key the runner sends as \"Bearer <key>\". It opens GetSystemInfo, the worker API in the runners namespace, and the health check."

  validation {
    condition     = can(regex("^[A-Za-z0-9]{32,}$", var.runner_token))
    error_message = "runner_token must be letters and digits, at least 32 of them."
  }
}

variable "tls_certificate" {
  type        = string
  description = "PEM of the certificate the proxy serves on 7233."

  validation {
    condition     = can(regex("-----BEGIN CERTIFICATE-----", var.tls_certificate))
    error_message = "tls_certificate must be a PEM certificate."
  }
}

variable "tls_private_key" {
  type        = string
  sensitive   = true
  description = "PEM of the private key of tls_certificate. Written to a file only the proxy can read."
}
