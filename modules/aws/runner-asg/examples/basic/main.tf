# Runner ASG wired to a VPC and ECR registry. Doubles as the CI plan/validate
# fixture; temporal_host and the images are placeholders a composition feeds forward
# after the cluster + Temporal are up.

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

module "vpc" {
  source = "../../../vpc"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
  cluster_name       = "acme-play-autoheal"
}

module "runner" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["runner"]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  temporal_host = "temporal.internal:7233"
  ecr_registry  = "111122223333.dkr.ecr.us-west-2.amazonaws.com"
  runner_image  = "111122223333.dkr.ecr.us-west-2.amazonaws.com/release/runner-go:latest"
  sandbox_image = "111122223333.dkr.ecr.us-west-2.amazonaws.com/dev/sandbox:latest"
}

output "asg_name" {
  value = module.runner.asg_name
}
