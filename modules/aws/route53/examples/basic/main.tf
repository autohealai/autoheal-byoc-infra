# Records for the Autoheal hostnames: aliases to a load balancer, an A record
# and a CNAME. Doubles as the CI validate fixture. The alias target would come
# from an ingress load balancer in a composition.

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
  lb = {
    name    = "k8s-autoheal-0123456789-0123456789abcdef.elb.us-west-2.amazonaws.com"
    zone_id = "Z18D5FSROUN65G"
  }
}

module "route53" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"

  zone_id = "Z0123456789ABCDEFGHIJ"
  records = {
    apex     = { name = "", type = "A", alias = local.lb }
    auth     = { name = "auth", type = "A", alias = local.lb }
    auth_app = { name = "auth-app", type = "A", alias = local.lb }
    temporal = { name = "temporal", type = "A", records = ["10.60.15.10"], ttl = 60 }
    docs     = { name = "docs", type = "CNAME", records = ["autoheal.acme.example"] }
  }
}

output "fqdns" {
  description = "Record names, keyed like the records input."
  value       = module.route53.fqdns
}
