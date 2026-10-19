terraform {
  required_version = ">= 1.7"

  # Provider pins only. The chart is installed by compositions/app, so this
  # composition has no helm or kubernetes provider.
  required_providers {
    # 6.59: the floor of modules/aws/aurora-postgres.
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.59, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
