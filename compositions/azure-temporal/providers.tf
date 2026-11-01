# The VM's subscription, the one of the Postgres server. Nothing is read or
# created in the cluster's subscription.
provider "azurerm" {
  features {
    # A change to the VM's custom data updates the scale set model only. The
    # operator reimages the VM when Temporal may restart (see the README).
    virtual_machine_scale_set {
      roll_instances_when_required = false
    }
  }
  subscription_id = var.subscription_id
}

provider "tls" {}

provider "random" {}
