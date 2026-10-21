# One customer managed key that CloudWatch Logs may also use. Doubles as the CI
# plan/validate fixture.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "kms" {
  source = "../../"

  # null-label (environment = lifecycle, not region); gives alias/acme-play-autoheal
  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  description             = "Autoheal acme-play data at rest"
  cloudwatch_logs_enabled = true
}

output "key_arn" {
  description = "ARN of the KMS key."
  value       = module.kms.key_arn
}

output "alias_name" {
  description = "Alias of the KMS key."
  value       = module.kms.alias_name
}
