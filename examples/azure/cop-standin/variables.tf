variable "subscription_id" {
  type        = string
  description = "The cluster's subscription (COP-test)."
}

variable "sre_subscription_id" {
  type        = string
  description = "Our subscription (SRE-test), where examples/azure/split/infra deploys. Used only for our side of the peering."
}

variable "location" {
  type        = string
  default     = "eastus2"
  description = "Azure region. Use the region of examples/azure/split/infra."
}

variable "admin_group_object_ids" {
  type        = list(string)
  description = "Entra groups that are cluster admins. The person running this apply must be in one of them, to create the namespace."
}

variable "deployer_object_id" {
  type        = string
  description = "Object ID of the identity that applies examples/azure/split. It gets only what a cluster owner gives us."
}

variable "network_cidr" {
  type        = string
  default     = "10.40.0.0/16"
  description = "Address space of the cluster's VNet. Must not overlap network_cidr of examples/azure/split/infra."
}

variable "namespace" {
  type        = string
  default     = "autoheal"
  description = "The namespace we are given."
}

variable "network_path" {
  type        = string
  default     = "private"
  description = "private for examples/azure/split (peering), public for examples/azure/split-public (static public IP and a storage service endpoint, no peering)."

  validation {
    condition     = contains(["private", "public"], var.network_path)
    error_message = "network_path must be private or public."
  }
}

variable "sre_vnet_id" {
  type        = string
  default     = ""
  description = "Private path only: the network.vnet_id output of examples/azure/split/infra. Empty on the first apply; set it after the infra apply to create both sides of the peering."
}
