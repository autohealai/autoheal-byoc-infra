# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The VMSS is named from the label id; its user-assigned identity is <id>-uai.

variable "resource_group_name" {
  type        = string
  description = "Resource group the VMSS lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "subnet_id" {
  type        = string
  description = "Runner subnet id (snet-runner from compositions/azure-runner, or the customer's). Egress is via that subnet's NAT gateway; the VMSS gets no public IP."
}

variable "acr_id" {
  type        = string
  default     = ""
  description = "ACR resource ID to grant the runner identity AcrPull on. Used only when acr_pull_enabled is true."
}

variable "acr_pull_enabled" {
  type        = bool
  default     = false
  description = "Grant the runner identity AcrPull on acr_id. Plan-time bool: acr_id is computed when the ACR is created in the same apply, so it cannot gate count. Leave false when images come from a public registry."
}

variable "acr_name" {
  type        = string
  default     = ""
  description = "ACR name for `az acr login -n` in the credential-refresh timer. Empty means the images are public: no Azure CLI is installed and no login runs."
}

variable "temporal_host" {
  type        = string
  description = "Temporal frontend host:port the runner polls, set as TEMPORAL_HOST: the chart's runner host on 443, e.g. runner.autoheal.acme.example:443, or the private address of a Temporal load balancer on 7233."
}

variable "temporal_tls" {
  type        = bool
  default     = true
  description = "Dial Temporal over TLS (TEMPORAL_TLS). True for the chart's runner host; false only for a Temporal load balancer on a private route."
}

variable "temporal_server_name" {
  type        = string
  default     = ""
  description = "Name the runner checks in the Temporal certificate (TEMPORAL_SERVER_NAME). Empty means the host of temporal_host."
}

variable "temporal_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Key the runner sends with each Temporal call (TEMPORAL_TOKEN): the vault entry runner-token that the chart's proxy checks on the runner host. Written to a root-only file on the VMs. Empty sends none."
}

variable "temporal_ca_certificate" {
  type        = string
  default     = ""
  description = "PEM of the CA that signed the Temporal certificate, when the system trust store does not have it, such as a private CA on the edge. The runner trusts it in addition to the system CAs. Empty adds none."

  validation {
    condition     = var.temporal_ca_certificate == "" || can(regex("-----BEGIN CERTIFICATE-----", var.temporal_ca_certificate))
    error_message = "temporal_ca_certificate must be empty or a PEM certificate."
  }
}

variable "tool_response_callback_url" {
  type        = string
  default     = ""
  description = "URL the runner posts sandbox tool results to, set as SANDBOX_TOOL_RESPONSE_CALLBACK_URL: the api-server-go internal listener, e.g. http://10.60.15.253:8083/api/v1/internal/sandbox-tool-responses. Empty leaves it unset and tool results go through Temporal only."

  validation {
    condition     = var.tool_response_callback_url == "" || can(regex("^https?://[^\\s]+$", var.tool_response_callback_url))
    error_message = "tool_response_callback_url must be empty or an http(s) URL."
  }
}

variable "runner_image" {
  type        = string
  description = "Fully qualified runner-go image, e.g. public.ecr.aws/e4h3h0d9/app/runner-go:chart-1.0.0."
}

variable "sandbox_image" {
  type        = string
  default     = ""
  description = "Fully qualified sandbox image to pre-pull on boot. Empty skips the pre-pull."
}

variable "upgrade_mode" {
  type        = string
  default     = "Manual"
  description = "VMSS upgrade mode. With Manual, an apply that changes the model (such as a new runner image tag) updates and reimages each instance, through the azurerm features roll_instances_when_required and reimage_on_manual_upgrade (both on by default). Automatic makes the provider start a rolling OS upgrade, which needs a health probe this module does not set, so such an apply fails."

  validation {
    condition     = contains(["Manual", "Automatic"], var.upgrade_mode)
    error_message = "upgrade_mode must be Manual or Automatic."
  }
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key for the admin user (break-glass; the SSM-equivalent is az run-command). No password auth."
}

variable "runner_name" {
  type        = string
  default     = "runner-byoc-aks"
  description = "NAME env the worker registers under."
}

variable "vm_sku" {
  type        = string
  default     = "Standard_D4s_v6"
  description = "VM size. Some policies forbid Intel Dsv5; D4s_v6 is validated."
}

variable "instance_count" {
  type        = number
  default     = 1
  description = "VMSS instance count. Each runner is an independent Temporal worker; scale out by raising this."
}

variable "max_concurrent_activities" {
  type        = number
  default     = 20
  description = "API_WORKER_MAX_CONCURRENT_ACTIVITIES per runner. 20 matches Autoheal's hosted runners on the same 4 vCPU, 16 GiB size."
}

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = "Admin username on the VMSS instances."
}

variable "os_disk_size_gb" {
  type        = number
  default     = 1024
  description = "OS disk size in GiB. Holds Docker layers, sandbox dirs and git datasource caches. Premium SSD speed grows with size: 1024 GiB is P30 (5000 IOPS, 200 MB/s), the smallest size at least as fast as the 3000 IOPS gp3 disk of Autoheal's hosted runners. 200 GiB (P15, 1100 IOPS) left the first chat after a boot waiting minutes on disk writes."
}
