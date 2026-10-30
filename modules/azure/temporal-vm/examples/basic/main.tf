# Temporal VM with start_temporal off: only the proxy runs. Doubles as the CI
# validate fixture. compositions/azure-temporal makes the keys, the certificate
# and the Postgres firewall rule; this fixture takes them as inputs.

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
  features {}
}

variable "runner_token" {
  type        = string
  sensitive   = true
  description = "The runner key: the runner_token output of compositions/azure."
}

variable "app_key" {
  type        = string
  sensitive   = true
  description = "The app key: any random string of 32 or more letters and digits."
}

variable "temporal_db_password" {
  type        = string
  sensitive   = true
  description = "Password of temporal_user: the temporal-db-password secret in the install's Key Vault."
}

variable "tls_certificate" {
  type        = string
  description = "PEM of the server certificate for temporal.autoheal.internal."
}

variable "tls_private_key" {
  type        = string
  sensitive   = true
  description = "PEM of the certificate's private key."
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

  app_key         = var.app_key
  runner_token    = var.runner_token
  tls_certificate = var.tls_certificate
  tls_private_key = var.tls_private_key

  admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAM example"
}

output "temporal_address" {
  description = "Address clients dial."
  value       = "${module.temporal.public_ip}:7233"
}
