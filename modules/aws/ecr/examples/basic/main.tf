# Pull through cache for the public Autoheal registry, with an IAM policy for
# the pullers. Doubles as the CI validate fixture. Set kms_key_arn to encrypt the
# cached repositories with a customer managed key.

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

module "ecr" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  repository_prefix = "acme-autoheal"
}

resource "aws_iam_policy" "ecr_pull" {
  name   = "acme-play-autoheal-ecr-pull"
  policy = module.ecr.pull_policy_json
}

output "image_registry" {
  description = "Value for the chart's global.imageRegistry."
  value       = module.ecr.image_registry
}

output "ecr_pull_policy_arn" {
  description = "Policy to attach to the node and runner roles."
  value       = aws_iam_policy.ecr_pull.arn
}
