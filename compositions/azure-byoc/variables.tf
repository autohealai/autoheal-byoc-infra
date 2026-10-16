# Inputs for the full Azure BYOC stack. The Terragrunt wrapper in
# examples/azure-byoc supplies these.

# ---------------------------------------------------------------------------
# Identity / naming (null-label; environment = lifecycle, not region)
# ---------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Customer / tenant, e.g. 'acme'. First element of every resource name."
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
  description = "Create privatelink DNS zones + private endpoints for Blob and Key Vault. This is the recommended runtime path for in-cluster pods. When false, the runtime path relies on workload_egress_ip_ranges (the cluster's outbound IP) or an Allow default action instead."
}

variable "deployer_ip_ranges" {
  type        = list(string)
  default     = []
  description = "APPLY-TIME path. Public egress CIDR(s) of the Terraform apply host, allow-listed on the Blob and Key Vault firewalls so the apply can create the blob container and seed Key Vault secrets over the data plane (deny-all blocks this otherwise). This is NOT a runtime path for pods — see workload_egress_ip_ranges. Leave empty only when the *_network_default_action values are \"Allow\"."
}

variable "workload_egress_ip_ranges" {
  type        = list(string)
  default     = []
  description = "RUNTIME path for the non-private-endpoint case. Public outbound/NAT CIDR(s) of the AKS cluster, allow-listed on the Blob and Key Vault firewalls so in-cluster ESO/app pods can reach them. This is the cluster's outbound IP, NOT the apply host's. NOTE: with the default AKS load balancer, Azure assigns this IP during cluster creation, so it is not known until after the first apply — using this path is an inherently two-stage flow (apply once with Allow or private endpoints, read the cluster's outbound IP, then set this and re-apply to tighten). Prefer private_endpoints_enabled = true, which needs no second stage."
}

variable "storage_network_default_action" {
  type        = string
  default     = "Deny"
  description = "Blob storage firewall default action. Deny (recommended) = only private endpoints, trusted Azure services, and the allow-listed CIDRs reach the account. Allow only for throwaway/playground installs."

  validation {
    condition     = contains(["Allow", "Deny"], var.storage_network_default_action)
    error_message = "storage_network_default_action must be exactly \"Allow\" or \"Deny\" (case-sensitive; the Azure API and the reachability preconditions reject any other value)."
  }
}

variable "key_vault_network_default_action" {
  type        = string
  default     = "Deny"
  description = "Key Vault firewall default action. Deny (recommended) = only private endpoints, trusted Azure services, and the allow-listed CIDRs reach the vault. Allow only for throwaway/playground installs."

  validation {
    condition     = contains(["Allow", "Deny"], var.key_vault_network_default_action)
    error_message = "key_vault_network_default_action must be exactly \"Allow\" or \"Deny\" (case-sensitive; the Azure API and the reachability preconditions reject any other value)."
  }
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

variable "admin_group_object_ids" {
  type        = list(string)
  default     = []
  description = "Entra (AAD) group object IDs granted cluster-admin via managed-AAD + Azure RBAC. Supplying any also disables the static-cert local admin accounts. Empty = Kubernetes RBAC only (no Entra integration)."
}

variable "aks_admin_tenant_id" {
  type        = string
  default     = ""
  description = "Entra tenant for AKS managed-AAD RBAC. Empty = the deploying provider's tenant. Only used when admin_group_object_ids is set."
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the public AKS API server. Empty = no IP restriction (production should set admin/CI egress CIDRs). Ignored when private_cluster_enabled = true."
}

variable "private_cluster_enabled" {
  type        = bool
  default     = false
  description = "Provision a private AKS control plane (no public API endpoint; reachable only from the VNet / peered networks). Default false = public endpoint restricted by api_server_authorized_ip_ranges. NOTE: when true, the API server is unreachable from the public internet, so the apply host, your kubectl, and the stage-2 app/Helm install must all have VNet connectivity (a jumpbox in the VNet, VPN/ExpressRoute, or a self-hosted runner on a peered network) plus private-DNS resolution of the cluster FQDN. Do not enable this without that connectivity in place."
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
  description = "Enable Key Vault purge protection (irreversible; leave false for play). Required when cmk_enabled = true."
}

# ---------------------------------------------------------------------------
# Backup, high availability and encryption at rest (Postgres + Blob + Key Vault)
#
# Every value below defaults to the stack's CURRENT behaviour, so an existing
# install is undisturbed until the install profile opts in. Set production values
# in examples/<install>/terragrunt.hcl. Three settings are IRREVERSIBLE or
# CREATE-TIME and are called out in their descriptions: Postgres geo-redundant
# backup and the customer-managed key are fixed at server-create time; the Key
# Vault soft-delete window and purge protection cannot change on an existing vault.
# Decide those before the first apply.
# ---------------------------------------------------------------------------

variable "postgres_backup_retention_days" {
  type        = number
  default     = 7
  description = "Days of automatic Postgres backups to keep (1-35); any point in the window can be restored. Recommended for production: 35."
}

variable "postgres_geo_redundant_backup_enabled" {
  type        = bool
  default     = false
  description = "Copy Postgres backups to the Azure paired region so they survive a whole-region outage. CREATE-TIME ONLY. Recommended for production: true. Cannot be combined with cmk_enabled yet: together they require a paired-region geo-backup key that is not yet supported, so enable one or the other."
}

variable "postgres_auto_grow_enabled" {
  type        = bool
  default     = false
  description = "Let Postgres storage expand automatically before it fills up (a full disk takes the database read-only). Default off to preserve existing behaviour; strongly recommended on for a real install."
}

variable "postgres_high_availability_enabled" {
  type        = bool
  default     = false
  description = "Run a hot Postgres standby in a second availability zone with automatic failover. Needs a zonal region and a GP_/MO_ SKU. Recommended for production: true."
}

variable "postgres_delete_protection_enabled" {
  type        = bool
  default     = false
  description = "Lock the Postgres server against deletion (deleting a server also deletes its backups). Recommended for production: true."
}

variable "blob_replication_type" {
  type        = string
  default     = "LRS"
  description = "Blob redundancy: LRS (copies within one datacentre), ZRS (across zones in the region), GRS/GZRS (also the paired region). Recommended for production: ZRS, or GRS to survive the loss of a whole region."
}

variable "blob_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Days a deleted blob can be recovered (0 = off). Recommended for production: 30."
}

variable "blob_container_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Days a deleted container can be recovered (0 = off). Protects the per-tenant Git Registry containers. Recommended for production: 30."
}

variable "blob_pitr_enabled" {
  type        = bool
  default     = false
  description = "Enable blob point-in-time restore (rewind the account's blobs to an earlier moment, e.g. after a bad bulk overwrite). Recommended for production: true."
}

variable "blob_restore_days" {
  type        = number
  default     = 6
  description = "How far back blob point-in-time restore can rewind, in days. Must be LESS than blob_soft_delete_retention_days. Ignored when blob_pitr_enabled = false."
}

variable "key_vault_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Days a deleted vault or secret can be recovered (7-90). CREATE-TIME ONLY. Recommended for production: 90."
}

variable "cmk_enabled" {
  type        = bool
  default     = false
  description = "Encrypt Postgres and Blob at rest with a customer-managed key created in this stack's Key Vault, instead of the Microsoft-managed key. Requires key_vault_purge_protection_enabled = true. CMK is CREATE-TIME ONLY on Postgres, so decide before the first apply. Off by default (data is still encrypted with the Microsoft-managed key). Cannot be combined with postgres_geo_redundant_backup_enabled yet: together they require a paired-region geo-backup key that is not yet supported, so enable one or the other. Because CMK is create-time only, changing it later forces a server rebuild; set postgres_delete_protection_enabled = false first, or the delete lock blocks the rebuild."
}
