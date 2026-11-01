# Temporal VM with start_temporal off: only the gate runs. Doubles as the CI
# validate fixture. compositions/azure-temporal makes the keys, the certificate,
# the Key Vault role assignments and the Postgres firewall rule; this fixture
# takes the vault and the entry names as inputs.

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    # The VM changes only when the operator reimages it.
    virtual_machine_scale_set {
      roll_instances_when_required = false
    }
  }
}

variable "temporal_db_password" {
  type        = string
  sensitive   = true
  description = "Password of temporal_user: the temporal-db-password secret in the install's Key Vault."
}

module "temporal" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["temporal"]

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  address_space        = "10.62.0.0/28"
  allowed_source_cidrs = ["198.51.100.20/32", "203.0.113.0/28"]

  temporal_server_image      = "public.ecr.aws/e4h3h0d9/external/temporal-server:1.29.0"
  temporal_admin_tools_image = "public.ecr.aws/e4h3h0d9/external/temporal-admin-tools:1.29.1-tctl-1.18.4-cli-1.5.0"
  proxy_image                = "public.ecr.aws/e4h3h0d9/external/envoy:distroless-v1.35.6"

  postgres_fqdn        = "acme-play-autoheal-db.postgres.database.azure.com"
  temporal_db_password = var.temporal_db_password

  # The VM's identity needs Key Vault Secrets User on each of these entries.
  key_vault_uri           = "https://kv-acme-play-autoheal.vault.azure.net/"
  certificate_secret_name = "temporal-tls"

  admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAM example"
}

output "temporal_address" {
  description = "Address clients dial."
  value       = "${module.temporal.public_ip}:7233"
}

output "identity_principal_id" {
  description = "Principal to grant Key Vault Secrets User on the key and certificate entries."
  value       = module.temporal.identity_principal_id
}
