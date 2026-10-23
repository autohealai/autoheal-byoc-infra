# Internal NLB in front of the Autoheal proxy: 443 to its TLS listener on 8443
# and 80 to its redirect listener on 8090, reachable from the VPC CIDR. Doubles
# as the CI validate fixture. The IDs are placeholders; a composition passes
# them from the vpc and eks modules.

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
  attributes  = ["edge"]

  vpc_id         = "vpc-0123456789abcdef0"
  vpc_cidr_block = "10.60.0.0/16"
  subnet_ids = [
    "subnet-0123456789abcdef0",
    "subnet-0123456789abcdef1",
    "subnet-0123456789abcdef2",
  ]

  listeners = {
    https = {
      port        = 443
      target_port = 8443
    }
    http = {
      port        = 80
      target_port = 8090
    }
  }

  allowed_cidr_blocks       = ["10.60.0.0/16"]
  target_security_group_ids = ["sg-0123456789abcdef1"]
}

output "dns_name" {
  description = "DNS name of the NLB, for the hostnames' records."
  value       = module.nlb.dns_name
}

output "target_group_arns" {
  description = "Target groups for the chart's TargetGroupBinding resources."
  value       = module.nlb.target_group_arns
}
