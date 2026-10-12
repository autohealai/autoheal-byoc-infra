# Minimal secret store. Doubles as the CI plan/validate fixture. Real values are
# fed by a composition through sensitive inputs; the placeholders below are not real.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "secrets" {
  source = "../../"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"

  secret_prefix = "tenants/avid"
  secrets = {
    "postgres-password" = "placeholder-not-real" # pragma: allowlist secret
  }
}

output "secret_store_uri" {
  value = module.secrets.secret_store_uri
}
