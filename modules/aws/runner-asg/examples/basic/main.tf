# Runner ASG that polls Temporal through the internal runner load balancer of
# compositions/aws. Doubles as the CI validate fixture. The VPC, subnets and
# load balancer addresses are placeholders compositions/aws-runner passes from
# compositions/aws (the network and runner_load_balancer outputs).

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
  chart_version = "1.0.0"
}

module "runner" {
  source = "../../"

  namespace   = "acme"
  environment = "prod"
  name        = "autoheal"
  attributes  = ["runner"]

  vpc_id = "vpc-0123456789abcdef0"
  subnet_ids = [
    "subnet-0123456789abcdef0",
    "subnet-0123456789abcdef1",
    "subnet-0123456789abcdef2",
  ]

  temporal_host              = "acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:7233"
  tool_response_callback_url = "http://acme-prod-autoheal-runner-0123456789abcdef.elb.us-west-2.amazonaws.com:8083/api/v1/internal/sandbox-tool-responses"
  runner_name                = "acme-prod-autoheal-runner"
  runner_image               = "public.ecr.aws/e4h3h0d9/app/runner-go:chart-${local.chart_version}"
  sandbox_image              = "public.ecr.aws/e4h3h0d9/app/sandbox:chart-${local.chart_version}"
}

output "runner_asg_name" {
  description = "Name of the runner Auto Scaling group."
  value       = module.runner.autoscaling_group_name
}
