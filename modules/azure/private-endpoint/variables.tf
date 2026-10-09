# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "resource_group_name" {
  type        = string
  description = "Resource group the endpoint lands in (created by the composition)."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "subnet_id" {
  type        = string
  description = "Subnet the PE NIC lands in (snet-pe from modules/azure/vnet; private_endpoint_network_policies must be Disabled)."
}

variable "target_resource_id" {
  type        = string
  description = "Resource id of the PaaS resource to privatize (storage account, key vault, Cognitive/AI Foundry account)."
}

variable "subresource_names" {
  type        = list(string)
  description = "Target sub-resource(s): [\"blob\"] for storage, [\"vault\"] for Key Vault, [\"account\"] for AI Foundry/Cognitive."
}

variable "private_dns_zone_ids" {
  type        = list(string)
  description = "Privatelink DNS zone ids to register the PE A-record in (VNet-linked by modules/azure/vnet)."
}
