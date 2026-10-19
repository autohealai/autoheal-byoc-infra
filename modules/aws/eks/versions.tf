terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.9.0 added aws_eks_cluster.deletion_protection.
      version = "~> 6.9"
    }
  }
}
