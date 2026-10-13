# Inputs for the Azure BYOC CONNECT composition. Unlike azure-byoc (create), this
# does not provision base infrastructure and so does NOT derive names from the
# null-label — the customer already built the VNet, AKS, PG, Key Vault, Redis, ACR
# and Storage, usually under their own naming. You therefore pass the existing
# resource names/RG explicitly; the only things this composition creates are the app
# and ESO workload identities (+ their federated credentials and role grants) and,
# optionally, seed secrets.

# ---------------------------------------------------------------------------
# Placement + existing resources (all in one resource group)
# ---------------------------------------------------------------------------

variable "subscription_id" {
  type        = string
  description = "Azure subscription the existing resources live in."
}

variable "location" {
  type        = string
  description = "Azure region of the existing resources (where the new app and ESO identities are created)."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group that holds the existing resources (and where the app and ESO identities are created)."
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the existing AKS cluster (must have the OIDC issuer enabled for workload identity)."
}

variable "postgres_server_name" {
  type        = string
  description = "Name of the existing PostgreSQL Flexible Server."
}

variable "key_vault_name" {
  type        = string
  description = "Name of the existing Key Vault (ESO reads app secrets from here)."
}

variable "redis_cache_name" {
  type        = string
  description = "Name of the existing Azure Cache for Redis."
}

variable "acr_name" {
  type        = string
  description = "Name of the existing Azure Container Registry."
}

variable "storage_account_name" {
  type        = string
  description = "Name of the existing Storage Account (attachments / knowledge base)."
}

variable "storage_container_name" {
  type        = string
  default     = "attachments"
  description = "Blob container used for attachments (reported in object_store; not created here)."
}

# ---------------------------------------------------------------------------
# App workload identity (the main thing this composition CREATES)
# ---------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Customer / tenant label for the app identity this composition creates, e.g. 'nomura'."
}

variable "environment" {
  type        = string
  description = "Lifecycle label (stage | prod | play) for the app identity, NOT region."
}

variable "name" {
  type        = string
  default     = "autoheal"
  description = "Component label for the app identity."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags on the resources this composition creates."
}

variable "federated_service_accounts" {
  type = list(object({
    namespace       = string
    service_account = string
  }))
  # Defaults match the Autoheal BYOC chart (same as the create composition): the
  # three app pods that read Blob (api-server-go attachments; agents prompt storage)
  # run in namespace "autoheal" with these ServiceAccount names. The chart annotates
  # them with runner_identity's client-id. Override only if the customer installs the
  # app into a different namespace or with different ServiceAccount names.
  default = [
    { namespace = "autoheal", service_account = "api-server-go" },
    { namespace = "autoheal", service_account = "agents-py-http" },
    { namespace = "autoheal", service_account = "agents-py-worker" },
  ]
  description = "Kubernetes service accounts federated to the app identity (subject system:serviceaccount:<ns>:<sa>). Match the app install."
}

variable "grant_app_acr_pull" {
  type        = bool
  default     = false
  description = "Also grant the app identity AcrPull on the existing ACR (kubelet identity usually covers pulls; set true only if the app pulls directly)."
}

# ---------------------------------------------------------------------------
# Optional secret seeding into the existing Key Vault
# ---------------------------------------------------------------------------

variable "seed_secrets_enabled" {
  type        = bool
  default     = true
  description = "Seed the data-tier secrets this composition can derive (redis-host/redis-port/redis-password, postgres-host, postgres-user) plus additional_secrets into the existing Key Vault. Requires the deployer to hold (or be granted here) Key Vault Secrets Officer. Set false if the customer manages their own secrets."
}

variable "postgres_admin_login" {
  type        = string
  default     = "pgadmin"
  description = "PG admin username to record as the postgres-user secret (the server's password is never readable via data source — pass it via additional_secrets)."
}

variable "additional_secrets" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Extra secret name -> value to seed into the existing Key Vault (e.g. postgres-password, which cannot be read back from the server). Merged over the derived set."
}
