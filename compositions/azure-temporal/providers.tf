# The VM's subscription, the one of the Postgres server. Nothing is read or
# created in the cluster's subscription.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "tls" {}

provider "random" {}
