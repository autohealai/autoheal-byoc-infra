terraform {
  # 1.7 for for_each in import blocks (import_federated_credentials).
  required_version = ">= 1.7"

  required_providers {
    # 4.65 for user_assigned_identity_id on federated credentials, 4.76 for the
    # fix to updating an imported one.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.76"
    }
  }
}
