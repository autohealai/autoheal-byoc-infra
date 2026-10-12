# Inputs for the full Azure BYOC stack. The Terragrunt wrapper in
# examples/azure-byoc supplies these.

# ---------------------------------------------------------------------------
# Identity / naming (null-label; environment = lifecycle, not region)
# ---------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Customer / tenant, e.g. 'avid'. First element of every resource name."
}

variable "environment" {
  type        = string
  description = "Lifecycle: stage | prod | play (NOT region)."
}

variable "name" {
  type        = string
  default     = "autoheal"
  description = "Component name; the middle element of resource names."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto every resource."
}

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "subscription_id" {
  type        = string
  description = "Azure subscription to deploy into."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a real Azure subscription GUID — did you leave the REPLACE_ME placeholder? Get it with: az account show --query id -o tsv"
  }
}

variable "location" {
  type        = string
  description = "Azure region (e.g. centralus). Region is implied here, not in the name."
}

variable "resource_group_name" {
  type        = string
  default     = ""
  description = "Resource group to create. Empty = derive 'rg-<namespace>-<environment>-<name>'. One RG per install = one teardown unit."
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "address_space" {
  type        = list(string)
  default     = ["10.60.0.0/16"]
  description = "VNet address space."
}

variable "private_endpoints_enabled" {
  type        = bool
  default     = false
  description = "Create privatelink DNS zones + private endpoints for Blob and Key Vault."
}

# ---------------------------------------------------------------------------
# PostgreSQL
# ---------------------------------------------------------------------------

variable "postgres_sku_name" {
  type        = string
  default     = "GP_Standard_D2ds_v5"
  description = "PG Flexible SKU. BYOC policy = provisioned (GP_/MO_)."
}

variable "postgres_storage_mb" {
  type        = number
  default     = 32768
  description = "PG Flexible storage (MB)."
}

# ---------------------------------------------------------------------------
# AKS
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  type        = string
  default     = null
  description = "AKS version. null = AKS default."
}

variable "node_vm_size" {
  type        = string
  default     = "Standard_D4s_v6"
  description = "Default node pool VM size."
}

variable "node_min_count" {
  type        = number
  default     = 2
  description = "Node pool autoscaler minimum."
}

variable "node_max_count" {
  type        = number
  default     = 4
  description = "Node pool autoscaler maximum."
}

# ---------------------------------------------------------------------------
# ACR
# ---------------------------------------------------------------------------

variable "acr_sku" {
  type        = string
  default     = "Standard"
  description = "ACR SKU: Basic | Standard | Premium."
}

# ---------------------------------------------------------------------------
# Workload identity
# ---------------------------------------------------------------------------

variable "federated_service_accounts" {
  type = list(object({
    namespace       = string
    service_account = string
  }))
  # Defaults match the Autoheal BYOC chart: the three app pods that read Blob
  # (api-server-go attachments; agents prompt storage) run in namespace "autoheal"
  # with these ServiceAccount names. The chart annotates them with runner_identity's
  # client-id. Override only if you install into a different namespace.
  default = [
    { namespace = "autoheal", service_account = "api-server-go" },
    { namespace = "autoheal", service_account = "agents-py-http" },
    { namespace = "autoheal", service_account = "agents-py-worker" },
  ]
  description = "Kubernetes service accounts federated to the app identity. Defaults match the autoheal-byoc chart's app SAs in namespace 'autoheal'."
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------

variable "key_vault_purge_protection_enabled" {
  type        = bool
  default     = false
  description = "Enable Key Vault purge protection (irreversible; leave false for play)."
}
