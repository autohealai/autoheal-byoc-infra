# Re-export the computed label values so consuming modules can reference
# module.this.id, module.this.tags, module.this.context, etc.

output "id" {
  description = "Disambiguated ID string restricted to id_length_limit characters."
  value       = module.this.id
}

output "id_full" {
  description = "Disambiguated ID string, not restricted in length."
  value       = module.this.id_full
}

output "enabled" {
  description = "Whether resources should be created."
  value       = module.this.enabled
}

output "namespace" {
  value = module.this.namespace
}

output "environment" {
  value = module.this.environment
}

output "stage" {
  value = module.this.stage
}

output "name" {
  value = module.this.name
}

output "attributes" {
  value = module.this.attributes
}

output "delimiter" {
  value = module.this.delimiter
}

output "label_order" {
  value = module.this.label_order
}

output "tags" {
  description = "Normalized tag map to apply to every resource."
  value       = module.this.tags
}

output "tags_as_list_of_maps" {
  value = module.this.tags_as_list_of_maps
}

output "normalized_context" {
  description = "Normalized context of this module."
  value       = module.this.normalized_context
}

output "context" {
  description = "Merged but not normalized context, for passing into child modules (context = module.this.context)."
  value       = module.this.context
}
