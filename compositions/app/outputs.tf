output "release_name" {
  description = "Helm release name."
  value       = helm_release.autoheal.name
}

output "namespace" {
  description = "Namespace of the release."
  value       = helm_release.autoheal.namespace
}

output "chart_version" {
  description = "Chart version Helm installed."
  value       = helm_release.autoheal.metadata.version
}

output "revision" {
  description = "Helm release revision. Increases by one on every upgrade."
  value       = helm_release.autoheal.metadata.revision
}
