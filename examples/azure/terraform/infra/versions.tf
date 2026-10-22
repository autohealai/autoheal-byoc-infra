terraform {
  # 1.11 for Azure DevOps: from that version the state backend fetches a new
  # sign-in token from the pipeline when the old one expires.
  required_version = ">= 1.11"

  # Where the state lives. The pipeline passes the names with
  # terraform init -backend-config=..., see pipelines/terraform.yml.
  backend "azurerm" {}
}
