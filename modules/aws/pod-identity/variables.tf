# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The label id is the role name.

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the role is for. The trust policy only accepts Pod Identity requests from this cluster, and the associations are created in it."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be a valid EKS cluster name (1-100 letters, digits, '-' or '_', starting with a letter or digit)."
  }
}

variable "associations" {
  type = list(object({
    namespace       = string
    service_account = string
  }))
  default     = []
  description = "Kubernetes service accounts that get this role, e.g. [{ namespace = \"autoheal\", service_account = \"api-server\" }]. Each pair becomes one Pod Identity association. Names must be known at plan time."

  validation {
    condition     = length(distinct([for a in var.associations : "${a.namespace}/${a.service_account}"])) == length(var.associations)
    error_message = "associations must not repeat a namespace and service_account pair."
  }

  validation {
    condition     = alltrue([for a in var.associations : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", a.namespace))])
    error_message = "associations namespace must be a valid Kubernetes namespace name (lowercase letters, digits and '-', at most 63 characters)."
  }

  validation {
    condition     = alltrue([for a in var.associations : length(a.service_account) <= 253 && can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", a.service_account))])
    error_message = "associations service_account must be a valid Kubernetes service account name (lowercase letters, digits, '-' and '.', at most 253 characters)."
  }
}

variable "association_enabled" {
  type        = bool
  default     = true
  description = "Create the Pod Identity associations. Set false to create only the role, when the deployer cannot call eks:CreatePodIdentityAssociation and someone else creates them."
}

variable "inline_policies" {
  type        = map(string)
  default     = {}
  description = "Inline IAM policy JSON documents for the role, keyed by policy name (e.g. { storage = data.aws_iam_policy_document.s3.json }). Keys must be known at plan time; the documents may come from the same apply."

  validation {
    condition     = alltrue([for k in keys(var.inline_policies) : can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", k))])
    error_message = "inline_policies keys are used as IAM policy names: 1-128 letters, digits or +=,.@_- characters."
  }
}

variable "managed_policy_arns" {
  type        = map(string)
  default     = {}
  description = "Managed IAM policy ARNs to attach to the role, keyed by a fixed name (e.g. { bedrock = aws_iam_policy.bedrock.arn }). Keys must be known at plan time; the ARNs may come from the same apply."

  validation {
    condition     = alltrue([for k in keys(var.managed_policy_arns) : can(regex("^[A-Za-z0-9_-]{1,64}$", k))])
    error_message = "managed_policy_arns keys must be 1-64 letters, digits, '_' or '-'."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  default     = ""
  description = "ARN of a managed policy to set as the role's permissions boundary. Empty sets none."

  validation {
    condition     = var.permissions_boundary_arn == "" || can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

variable "role_path" {
  type        = string
  default     = "/"
  description = "IAM path for the role. Must start and end with '/'."

  validation {
    condition     = length(var.role_path) <= 512 && can(regex("^/([\\x21-\\x7E]*/)?$", var.role_path))
    error_message = "role_path must start and end with '/' and use printable ASCII characters (at most 512)."
  }
}

variable "max_session_duration" {
  type        = number
  default     = 3600
  description = "Maximum session length in seconds for the role (3600-43200). The Pod Identity agent refreshes credentials before they expire."

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}
