# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the EKS cluster OIDC provider (modules/aws/eks output oidc_provider_arn)."
}

variable "oidc_provider_url" {
  type        = string
  description = "URL of the EKS cluster OIDC issuer (modules/aws/eks output oidc_provider_url), e.g. https://oidc.eks.<region>.amazonaws.com/id/XXXX."
}

variable "federated_service_accounts" {
  type = list(object({
    namespace       = string
    service_account = string
  }))
  description = "Kubernetes service accounts allowed to assume this role (trust subject system:serviceaccount:<namespace>:<service_account>)."

  validation {
    condition     = length(var.federated_service_accounts) > 0
    error_message = "Provide at least one federated service account."
  }
}

variable "role_name_override" {
  type        = string
  default     = ""
  description = "Force an exact IAM role name. Empty derives '<label id>-irsa'."
}

variable "secret_arns" {
  type        = list(string)
  default     = []
  description = "Secret ARNs (or wildcards like '<prefix>/*') the app may read. Empty skips the secrets statement."
}

variable "s3_bucket_arns" {
  type        = list(string)
  default     = []
  description = "S3 bucket ARNs the app may read/write (object access is granted on '<arn>/*'). Empty skips the S3 statements."
}

variable "extra_policy_arns" {
  type        = list(string)
  default     = []
  description = "Additional managed/customer policy ARNs to attach to the role."
}
