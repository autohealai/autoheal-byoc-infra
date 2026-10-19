terraform {
  required_version = ">= 1.7"

  required_providers {
    # 6.45 stops a perpetual engine_version diff on Valkey. 6.58 stops a
    # perpetual diff while changes wait for the maintenance window
    # (apply_immediately = false).
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.58, < 7.0"
    }
  }
}
