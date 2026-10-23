# The identities' subscription, from the federation input of compositions/azure.
# The federated credentials are created there.
provider "azurerm" {
  features {}
  subscription_id                 = var.federation.subscription_id
  resource_provider_registrations = "none"
}

# The cluster's subscription. Only the cluster is read through it, so nothing is
# created there and no resource provider is registered.
provider "azurerm" {
  alias = "cluster"
  features {}
  subscription_id                 = var.cluster.subscription_id
  resource_provider_registrations = "none"
}
