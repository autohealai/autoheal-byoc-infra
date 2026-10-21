# Secrets for one install, encrypted with a customer managed key. Doubles as the
# CI validate fixture. The KMS key ARN is a placeholder; the composition passes
# the kms module output. The database password is generated in the same apply,
# which shows that values may be unknown at plan time.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

resource "random_password" "postgres" {
  length  = 32
  special = false
}

module "secrets" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  name_prefix = "acme-play-autoheal/"
  kms_key_arn = "arn:aws:kms:us-west-2:111122223333:key/00000000-0000-0000-0000-000000000000"

  secret_names = ["postgres-password", "llm-api-key"]
  secret_values = {
    "postgres-password" = random_password.postgres.result
    "llm-api-key"       = "REPLACE_ME_IN_composition" # pragma: allowlist secret
  }
}

output "secret_names" {
  description = "Full secret name per entry."
  value       = module.secrets.secret_names
}

output "arn_pattern" {
  description = "ARN pattern for GetSecretValue in a Pod Identity policy."
  value       = module.secrets.arn_pattern
}
