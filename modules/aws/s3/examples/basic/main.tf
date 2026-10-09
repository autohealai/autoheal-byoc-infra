# Minimal attachments bucket. Doubles as the CI plan/validate fixture.

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

module "s3" {
  source = "../../"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"
  attributes  = ["attachments"]
}

output "bucket_name" {
  value = module.s3.bucket_name
}
