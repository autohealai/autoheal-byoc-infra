# The runner's subscription, usually the data subscription of compositions/azure.
# Nothing is read or created in the cluster's subscription.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "tls" {}
