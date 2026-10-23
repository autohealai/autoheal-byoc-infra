# Outputs for compositions/app and for people. None of them holds a secret.

output "cluster" {
  description = "Cluster connection details for compositions/app: cloud, name, resource_group, subscription_id, endpoint and base64 ca_certificate. Use it instead of the cluster output of compositions/azure, whose endpoint and ca_certificate are empty for a brought cluster. Authentication is kubelogin with Entra ID; no credential is output."
  # The CA certificate and endpoint are not secret, so they leave the sensitive
  # marking of kube_config behind.
  value = {
    cloud           = "azure"
    name            = var.cluster.name
    resource_group  = var.cluster.resource_group
    subscription_id = var.cluster.subscription_id
    endpoint        = try(nonsensitive(data.azurerm_kubernetes_cluster.this.kube_config[0].host), data.azurerm_kubernetes_cluster.this.kube_config[0].host)
    ca_certificate  = try(nonsensitive(data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate), data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer, which the federated credentials trust."
  value       = local.oidc_issuer_url
}

output "federated_credentials" {
  description = "The federated credentials, as readable lines: identity, credential name and subject."
  value = sort([
    for c in values(local.federated_credentials) : "${split("/", c.identity_id)[8]}: ${c.name} (${c.subject})"
  ])
}
