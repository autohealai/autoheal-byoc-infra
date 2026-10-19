# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "zone_id" {
  type        = string
  description = "ID of the existing public or private Route 53 hosted zone, e.g. Z0123456789ABCDEFGHIJ."

  validation {
    condition     = can(regex("^Z[A-Z0-9]{1,31}$", var.zone_id))
    error_message = "zone_id must be a Route 53 hosted zone ID such as Z0123456789ABCDEFGHIJ (without /hostedzone/)."
  }
}

variable "records" {
  type = map(object({
    name    = string
    type    = string
    ttl     = optional(number, 300)
    records = optional(list(string), [])
    alias = optional(object({
      name                   = string
      zone_id                = string
      evaluate_target_health = optional(bool, true)
    }))
  }))
  description = "Records keyed by a stable key. name is relative to the zone (auth for auth.<zone>, empty for the apex) or fully qualified. type is A or CNAME. An A record has either records (IPv4 addresses) or alias (a load balancer DNS name and its hosted zone ID); a CNAME has exactly one record. ttl is ignored for aliases."

  validation {
    condition     = alltrue([for r in values(var.records) : contains(["A", "CNAME"], r.type)])
    error_message = "Each record type must be A or CNAME."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.alias == null || r.type == "A"])
    error_message = "alias is only allowed on A records."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.alias == null ? length(r.records) > 0 : length(r.records) == 0])
    error_message = "Each record needs either records or alias, not both and not neither."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.type != "CNAME" || (length(r.records) == 1 && r.name != "")])
    error_message = "A CNAME record needs exactly one value and cannot be at the zone apex."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.ttl >= 0 && r.ttl <= 2147483647])
    error_message = "ttl must be between 0 and 2147483647 seconds."
  }
}
