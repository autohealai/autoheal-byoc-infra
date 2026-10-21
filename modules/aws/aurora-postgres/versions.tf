terraform {
  required_version = ">= 1.7"

  required_providers {
    # 6.54 added auto_minor_version_upgrade on aws_rds_cluster. 6.59 stops a
    # pinned engine_version from planning a downgrade after AWS applies an
    # automatic minor upgrade.
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
