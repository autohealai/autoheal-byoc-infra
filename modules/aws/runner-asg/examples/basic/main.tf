# Runner ASG pulling from a private ECR mirror and polling Temporal through an
# internal NLB, all in one apply. Doubles as the CI validate fixture. The VPC,
# subnet and EKS security group IDs are placeholders a composition passes from
# the vpc and eks modules. Leave out ecr_registry_host and the ecr-pull policy
# when the images are public.

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

locals {
  vpc_id = "vpc-0123456789abcdef0"
  private_subnet_ids = [
    "subnet-0123456789abcdef0",
    "subnet-0123456789abcdef1",
    "subnet-0123456789abcdef2",
  ]
  chart_version = "1.0.0"
}

module "ecr" {
  source = "../../../ecr"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  repository_prefix = "acme-autoheal"
}

resource "aws_iam_policy" "ecr_pull" {
  name        = "acme-play-autoheal-ecr-pull"
  description = "Pull Autoheal images through the ECR pull-through cache."
  policy      = module.ecr.pull_policy_json
}

module "nlb" {
  source = "../../../nlb"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["internal"]

  vpc_id         = local.vpc_id
  vpc_cidr_block = "10.60.0.0/16"
  subnet_ids     = local.private_subnet_ids

  listeners = {
    temporal = {
      port = 7233
    }
    api_internal = {
      port         = 8083
      health_check = { protocol = "HTTP", path = "/health" }
    }
  }

  allowed_security_group_ids = [module.runner.security_group_id]
  target_security_group_ids  = ["sg-0123456789abcdef1"]
}

module "runner" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["runner"]

  vpc_id     = local.vpc_id
  subnet_ids = local.private_subnet_ids

  temporal_host              = "${module.nlb.dns_name}:7233"
  tool_response_callback_url = "http://${module.nlb.dns_name}:8083/api/v1/internal/sandbox-tool-responses"
  runner_name                = "runner-byoc-eks"
  runner_image               = "${module.ecr.image_registry}/app/runner-go:chart-${local.chart_version}"
  sandbox_image              = "${module.ecr.image_registry}/app/sandbox:chart-${local.chart_version}"

  ecr_registry_host          = module.ecr.registry_host
  additional_iam_policy_arns = { ecr-pull = aws_iam_policy.ecr_pull.arn }
}

output "runner_asg_name" {
  description = "Name of the runner Auto Scaling group."
  value       = module.runner.autoscaling_group_name
}
