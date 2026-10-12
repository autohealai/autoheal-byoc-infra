# App IRSA role trusting an EKS OIDC provider. Doubles as the CI plan/validate
# fixture; the OIDC/secret/bucket ARNs are placeholders a composition feeds forward.

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

module "irsa" {
  source = "../../"

  namespace   = "avid"
  environment = "play"
  name        = "autoheal"

  oidc_provider_arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"
  oidc_provider_url = "https://oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"

  federated_service_accounts = [
    { namespace = "autoheal", service_account = "api-server-go" },
  ]

  secret_arns    = ["arn:aws:secretsmanager:us-west-2:111122223333:secret:tenants/avid/*"]
  s3_bucket_arns = ["arn:aws:s3:::avid-play-autoheal-attachments"]
}

output "role_arn" {
  value = module.irsa.role_arn
}
