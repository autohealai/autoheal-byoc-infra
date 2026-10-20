# The cluster's subscription (COP). The stand-in plays the cluster owner, so it
# runs with admin rights here.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Our subscription (SRE), for our side of the peering only.
provider "azurerm" {
  alias = "sre"
  features {}
  subscription_id                 = var.sre_subscription_id
  resource_provider_registrations = "none"
}

# Creates the namespace. The person running the apply must be in one of
# admin_group_object_ids, which are cluster admins.
provider "kubernetes" {
  host                   = module.aks.host
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
  }
}
