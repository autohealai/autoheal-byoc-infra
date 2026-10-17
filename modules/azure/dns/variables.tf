# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "zone_name" {
  type        = string
  description = "Name of the existing public or private DNS zone, e.g. autoheal.acme.example."
}

variable "zone_resource_group_name" {
  type        = string
  description = "Resource group that holds the zone."
}

variable "records" {
  type        = map(string)
  description = "Record name relative to the zone (\"@\" for the apex) to the IPv4 address it points at."
}

variable "ttl" {
  type        = number
  default     = 300
  description = "Record TTL in seconds."
}

variable "private_zone" {
  type        = bool
  default     = false
  description = "true when the zone is an Azure Private DNS zone (privateDnsZones); false for a public DNS zone (dnszones)."
}
