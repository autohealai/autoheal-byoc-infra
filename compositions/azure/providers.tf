provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# The cluster's subscription: the subscription in existing_aks_cluster_id, or
# subscription_id when we create the cluster. Only two data sources use it (the
# cluster and its AKS subnet), so nothing is ever created through it. It registers
# no resource providers, because the deployer may only read in that subscription.
provider "azurerm" {
  alias = "cluster"
  features {}
  subscription_id                 = local.cluster_subscription_id
  resource_provider_registrations = "none"
}
