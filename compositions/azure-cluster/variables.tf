variable "cluster" {
  type = object({
    name            = string
    resource_group  = string
    subscription_id = string
  })
  description = "The cluster output of compositions/azure: name, resource_group and subscription_id of the brought cluster. Its other attributes are ignored."
}

variable "federation" {
  type = object({
    subscription_id = string
    identities = map(object({
      identity_id = string
      service_accounts = list(object({
        namespace       = string
        service_account = string
      }))
    }))
  })
  description = "The federation output of compositions/azure: subscription_id, where the identities are, and per identity its resource ID and the chart service accounts it trusts. Null when compositions/azure created the cluster, which this composition is not for."

  validation {
    condition     = var.federation != null
    error_message = "federation is null: compositions/azure created the cluster and federated the identities to it already. This composition is only for a brought cluster (existing_aks_cluster_id)."
  }

  validation {
    condition = var.federation == null ? true : alltrue([
      for identity in values(var.federation.identities) :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ManagedIdentity/userAssignedIdentities/[^/]+$", identity.identity_id))
    ])
    error_message = "Every federation.identities[*].identity_id must be the resource ID of a Microsoft.ManagedIdentity/userAssignedIdentities resource."
  }
}

variable "import_federated_credentials" {
  type        = bool
  default     = false
  description = "Import the federated credentials instead of creating them. Set it for one apply when upgrading from infra 3.x with a brought cluster, after removing the credentials from the state of compositions/azure (see the README), so pods keep their federation through the upgrade. Leave false for a new install."
}
