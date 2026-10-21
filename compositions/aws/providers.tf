# Credentials come from the environment (AWS_PROFILE, SSO or a CI role).
# allowed_account_ids stops an apply that runs with credentials for another
# account before it changes anything.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
}

provider "random" {}
