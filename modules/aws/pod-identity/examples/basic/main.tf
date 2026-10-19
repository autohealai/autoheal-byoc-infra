# One Pod Identity role with an inline S3 policy, bound to one service account.
# Doubles as the CI plan/validate fixture. The cluster name is a placeholder; in
# a real root it comes from modules/aws/eks.

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

data "aws_iam_policy_document" "storage" {
  statement {
    sid       = "ReadWriteAttachments"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::acme-play-autoheal-attachments/*"]
  }

  statement {
    sid       = "ListAttachments"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::acme-play-autoheal-attachments"]
  }
}

module "api_server_role" {
  source = "../../"

  # null-label (environment = lifecycle, not region); gives acme-play-autoheal-api-server
  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["api-server"]

  cluster_name = "acme-play-autoheal"
  associations = [
    { namespace = "autoheal", service_account = "api-server" },
  ]

  inline_policies = {
    storage = data.aws_iam_policy_document.storage.json
  }
}

output "role_arn" {
  description = "ARN of the IAM role."
  value       = module.api_server_role.role_arn
}

output "association_arns" {
  description = "Association ARNs by namespace/service account."
  value       = module.api_server_role.association_arns
}
