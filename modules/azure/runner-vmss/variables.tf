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
  description = "Runner subnet id (snet-runner from modules/azure/vnet). Egress is via that subnet's NAT gateway; the VMSS gets no public IP."
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
  description = "Temporal frontend host:port the runner polls, e.g. 10.60.15.253:7233 (the reserved internal address of the Temporal load balancer)."
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
  default     = 5
  description = "API_WORKER_MAX_CONCURRENT_ACTIVITIES per runner."
}

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = "Admin username on the VMSS instances."
}

variable "os_disk_size_gb" {
  type        = number
  default     = 200
  description = "OS disk size. Holds Docker layers + sandbox dirs + git datasource caches; 30GB proved insufficient on the EC2 runner, so default large."
}
