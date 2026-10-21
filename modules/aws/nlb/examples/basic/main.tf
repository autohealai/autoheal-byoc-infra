# Internal NLB in front of Temporal and the api-server-go internal listener,
# reachable from the runner security group. Doubles as the CI validate
# fixture. The IDs are placeholders; a composition passes them from the vpc,
# eks and runner-asg modules.

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

module "nlb" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["internal"]

  vpc_id         = "vpc-0123456789abcdef0"
  vpc_cidr_block = "10.60.0.0/16"
  subnet_ids = [
    "subnet-0123456789abcdef0",
    "subnet-0123456789abcdef1",
    "subnet-0123456789abcdef2",
  ]

  listeners = {
    temporal = {
      port = 7233
    }
    api_internal = {
      port         = 8083
      health_check = { protocol = "HTTP", path = "/health" }
    }
  }

  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  target_security_group_ids  = ["sg-0123456789abcdef1"]
}

output "temporal_host" {
  description = "Value for the runner's temporal_host."
  value       = "${module.nlb.dns_name}:7233"
}

output "target_group_arns" {
  description = "Target groups for the chart's TargetGroupBinding resources."
  value       = module.nlb.target_group_arns
}
