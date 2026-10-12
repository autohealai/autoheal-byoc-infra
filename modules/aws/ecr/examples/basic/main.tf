# Minimal registry with two repositories. Doubles as the CI plan/validate fixture.

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

module "ecr" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  repository_names = [
    "release/api-server-go",
    "release/runner-go",
  ]
}

output "registry_url" {
  value = module.ecr.registry_url
}
