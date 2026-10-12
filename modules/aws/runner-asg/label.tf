# Naming and tagging via the repo's shared label base (modules/_shared/label),
# the harness-label equivalent. This file is the per-module copyable template:
# it declares the label inputs and forwards them to the shared, version-pinned
# base. Reference module.this.id / module.this.tags in the resources.
#
# Policy defaults (repo convention, see docs/MODULE_STANDARD.md):
#   - environment = lifecycle (stage/prod/play), NOT region
#   - label_order drops "stage": [namespace, environment, name, attributes]

module "this" {
  source = "../../_shared/label"

  enabled     = var.enabled
  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = var.attributes
  tags        = var.tags
  label_order = var.label_order

  context = var.context
}

variable "context" {
  type = any
  default = {
    enabled             = true
    namespace           = null
    tenant              = null
    environment         = null
    stage               = null
    name                = null
    delimiter           = null
    attributes          = []
    tags                = {}
    additional_tag_map  = {}
    regex_replace_chars = null
    label_order         = []
    id_length_limit     = null
    label_key_case      = null
    label_value_case    = null
    descriptor_formats  = {}
    labels_as_tags      = ["unset"]
  }
  description = "Single object to set the entire naming/tagging context at once (inheritance from the composition). Individual non-null inputs below override it."
}

variable "enabled" {
  type        = bool
  default     = null
  description = "Set to false to prevent the module from creating any resources."
}

variable "namespace" {
  type        = string
  default     = null
  description = "ID element. Customer/tenant, e.g. 'avid'."
}

variable "environment" {
  type        = string
  default     = null
  description = "ID element. Lifecycle (stage/prod/play) in this repo — NOT region."
}

variable "name" {
  type        = string
  default     = null
  description = "ID element. Component name, e.g. 'autoheal'."
}

variable "attributes" {
  type        = list(string)
  default     = []
  description = "ID element. Extra qualifiers appended to id, e.g. ['db']."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags, merged into the generated tag set."
}

variable "label_order" {
  type        = list(string)
  default     = ["namespace", "environment", "name", "attributes"]
  description = "Order of ID elements in id. Repo default drops 'stage'."
}
