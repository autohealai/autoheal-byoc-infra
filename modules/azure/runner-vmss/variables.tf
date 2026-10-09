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
  description = "ACR resource id to grant the runner identity AcrPull."
}

variable "acr_name" {
  type        = string
  description = "ACR registry name (for `az acr login -n` in the credential-refresh timer)."
}

variable "temporal_host" {
  type        = string
  description = "Temporal frontend as host:port, the internal LB (e.g. 10.60.0.7:7233). The runner polls the `runners` namespace here."
}

variable "runner_image" {
  type        = string
  description = "Fully-qualified runner-go image, e.g. <acr>.azurecr.io/release/runner-go:<ver>."
}

variable "sandbox_image" {
  type        = string
  description = "Fully-qualified sandbox image pre-pulled on boot, e.g. <acr>.azurecr.io/dev/sandbox:latest."
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
