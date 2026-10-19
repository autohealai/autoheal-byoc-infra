# Module-specific inputs. Naming/tagging inputs (namespace, environment, name,
# attributes, tags, ...) are declared in label.tf and feed modules/_shared/label.
# The repository creation role is named <id>-ecr-template (cut to 64 characters
# with a hash suffix when longer).

variable "repository_prefix" {
  type        = string
  description = "ECR repository prefix for the pull through cache rule, e.g. autoheal. Images are pulled as <registry_host>/<repository_prefix>/<upstream path>. 2 to 30 characters, lowercase."

  validation {
    condition     = length(var.repository_prefix) >= 2 && length(var.repository_prefix) <= 30
    error_message = "repository_prefix must be 2 to 30 characters long."
  }

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.repository_prefix)) && var.repository_prefix != "ROOT"
    error_message = "repository_prefix must be lowercase letters, digits and . _ - / separators, start and end with a letter or digit, and not be ROOT."
  }
}

variable "upstream_registry_url" {
  type        = string
  default     = "public.ecr.aws"
  description = "Registry host the cache pulls from, without a scheme. The default is ECR Public, which needs no credentials."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?$", var.upstream_registry_url))
    error_message = "upstream_registry_url must be a registry host name such as public.ecr.aws, without https:// or a path."
  }
}

variable "upstream_namespace" {
  type        = string
  default     = "e4h3h0d9"
  description = "Path under the upstream registry that holds the chart images (app/<name> and external/<name>). It becomes part of image_registry. Empty when the images sit at the registry root."

  validation {
    condition     = var.upstream_namespace == "" || can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.upstream_namespace))
    error_message = "upstream_namespace must be empty or a lowercase repository path without leading or trailing slashes."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = ""
  description = "KMS key ARN for the cached repositories. Empty uses AES256 (ECR managed keys). The key policy must let IAM policies in the account grant use of the key (modules/aws/kms always does)."

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>)."
  }
}

variable "image_tag_mutability" {
  type        = string
  default     = "IMMUTABLE"
  description = "Tag mutability of the cached repositories. With IMMUTABLE, ECR does not update a cached tag when upstream moves it, which suits the pinned chart-<version> tags. Use MUTABLE to follow moving tags."

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "untagged_expiry_days" {
  type        = number
  default     = 14
  description = "Days after which untagged images in the cached repositories expire. Images referenced by a tagged multi-architecture index are not expired while the index exists."

  validation {
    condition     = var.untagged_expiry_days >= 1 && floor(var.untagged_expiry_days) == var.untagged_expiry_days
    error_message = "untagged_expiry_days must be a whole number of at least 1."
  }
}
