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
  description = "Scope the control-plane UAMI gets Network Contributor on (create mode, custom VNet): the VNet ID, or the node subnet ID when the network belongs to someone else."
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

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the public AKS API server. Empty = no IP restriction; set your admin/CI egress CIDRs for production. Ignored when private_cluster_enabled = true (a private cluster has no public endpoint)."
}

variable "private_cluster_enabled" {
  type        = bool
  default     = false
  description = "Provision a private control plane: the API server is reachable only from the VNet and peered/connected networks, with no public endpoint. Default false = public endpoint (restrict it with api_server_authorized_ip_ranges). Whatever runs kubectl/Terraform must have in-VNet connectivity when true."
}

variable "admin_group_object_ids" {
  type        = list(string)
  default     = []
  description = "Entra (AAD) group object IDs granted cluster-admin via managed-AAD + Azure RBAC. Empty = Kubernetes RBAC only (no managed-AAD integration). Deployment-specific, so there is no default."
}

variable "tenant_id" {
  type        = string
  default     = ""
  description = "Entra tenant for managed-AAD RBAC. Empty = the current provider's tenant. Only used when admin_group_object_ids is set."
}

variable "acr_id" {
  type        = string
  default     = ""
  description = "ACR resource id to grant the kubelet identity AcrPull on. Empty skips (e.g. pull-through or public registry)."
}

variable "acr_pull_enabled" {
  type        = bool
  default     = true
  description = "Grant the kubelet identity AcrPull on var.acr_id. Plan-time bool: acr_id is usually a computed ACR id (module.acr.acr_id), which cannot gate count directly — so a composition that creates its ACR must gate on this instead. Set false (with acr_id empty) for pull-through / public-registry clusters."
}

variable "entra_integration_enabled" {
  type        = bool
  default     = true
  description = "Turn on Entra (AAD) integration with Azure RBAC so clients log in with kubelogin. Default true. Local accounts stay enabled unless admin_group_object_ids is set."
}

variable "key_vault_secrets_provider_enabled" {
  type        = bool
  default     = true
  description = "Enable the Key Vault secrets provider (CSI driver) add-on, which the chart uses to read the vault."
}

variable "secret_rotation_interval" {
  type        = string
  default     = "2m"
  description = "How often the CSI driver polls the vault for changed secrets."
}
