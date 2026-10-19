# Module-specific inputs. Naming and tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "name_prefix" {
  type        = string
  description = "Prefix of every secret name, for example \"acme-prod-autoheal/\". Each secret is named <name_prefix><entry>, and arn_pattern grants access by this prefix, so end it with \"/\" or \"-\"."

  validation {
    condition     = can(regex("^[A-Za-z0-9/_+=.@-]{1,256}$", var.name_prefix))
    error_message = "name_prefix must be 1 to 256 characters from letters, digits and / _ + = . @ -."
  }

  validation {
    condition     = endswith(var.name_prefix, "/") || endswith(var.name_prefix, "-")
    error_message = "name_prefix must end with \"/\" or \"-\", so arn_pattern does not also match secrets of a longer prefix."
  }
}

variable "secret_names" {
  type        = list(string)
  description = "Entry names, one secret each (for example \"postgres-password\"). Not sensitive: they decide which secrets exist and must be known at plan time."

  validation {
    condition     = alltrue([for n in var.secret_names : can(regex("^[A-Za-z0-9/_+=.@-]+$", n))])
    error_message = "Each secret_names entry must be non-empty and use only letters, digits and / _ + = . @ -."
  }

  validation {
    condition     = length(distinct(var.secret_names)) == length(var.secret_names)
    error_message = "secret_names must not repeat an entry."
  }
}

variable "secret_values" {
  type        = map(string)
  sensitive   = true
  description = "Secret string per entry, keyed by the names in secret_names. Values may come from resources created in the same apply. Keys not in secret_names are ignored. Values are stored in Terraform state."
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN that encrypts the secrets."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "recovery_window_in_days" {
  type        = number
  default     = 30
  description = "Days a deleted secret can still be restored. 0 deletes it at once, which lets a secret with the same name be created again right away."

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "replica_regions" {
  type        = list(string)
  default     = []
  description = "Regions to replicate every secret to, for example [\"us-east-1\"]. Empty means no replicas."

  validation {
    condition     = alltrue([for r in var.replica_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "Each replica_regions entry must be a region name such as us-east-1."
  }

  validation {
    condition     = length(distinct(var.replica_regions)) == length(var.replica_regions)
    error_message = "replica_regions must not repeat a region."
  }
}

variable "replica_kms_key_arns" {
  type        = map(string)
  default     = {}
  description = "KMS key ARN per replica region. A region not in the map uses the replica of kms_key_arn when that is a multi-Region key (mrk-), otherwise the AWS managed key aws/secretsmanager in that region."

  validation {
    condition     = alltrue([for r, k in var.replica_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:${r}:", k))])
    error_message = "Each replica_kms_key_arns value must be a KMS key ARN in the region of its key."
  }
}
