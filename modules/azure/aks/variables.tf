# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The cluster is named from the label id; its control-plane identity is <id>-uami.

variable "resource_group_name" {
  type        = string
  description = "Resource group the cluster lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "create_cluster" {
  type        = bool
  default     = true
  description = "true (default) provisions the cluster; false connects to an existing cluster (same label id) in var.resource_group_name and creates no cluster resources (the AWS eks module's create_cluster analogue)."
}

variable "kubernetes_version" {
  type        = string
  default     = null
  description = "Kubernetes version (create mode). null = AKS default."
}

variable "vnet_id" {
  type        = string
  default     = ""
  description = "VNet id the control-plane UAMI gets Network Contributor on (create mode, custom VNet)."
}

variable "vnet_subnet_id" {
  type        = string
  default     = ""
  description = "Subnet id for the default node pool (create mode); modules/azure/vnet output subnet_aks_id."
}

variable "network_role_enabled" {
  type        = bool
  default     = true
  description = "Grant the control-plane UAMI Network Contributor on var.vnet_id (create mode, custom VNet). Must be a plan-time bool: vnet_id is a computed id, so it cannot gate count directly. Set false only for an AKS-managed VNet."
}

variable "sku_tier" {
  type        = string
  default     = "Standard"
  description = "AKS SKU tier: Free | Standard | Premium."
}

variable "node_vm_size" {
  type        = string
  default     = "Standard_D4s_v6"
  description = "Default node pool VM size. Some policies forbid Intel Dsv5; D4s_v6 is the validated SKU."
}

variable "node_min_count" {
  type        = number
  default     = 2
  description = "Default node pool autoscaler minimum."
}

variable "node_max_count" {
  type        = number
  default     = 4
  description = "Default node pool autoscaler maximum."
}

variable "acr_id" {
  type        = string
  default     = ""
  description = "ACR resource id to grant the kubelet identity AcrPull on. Empty skips (e.g. pull-through or public registry)."
}
