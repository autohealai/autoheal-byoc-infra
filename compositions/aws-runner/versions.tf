terraform {
  required_version = ">= 1.7"

  # Provider pins only. The runner never reads the cluster, so this composition
  # has no helm or kubernetes provider.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
