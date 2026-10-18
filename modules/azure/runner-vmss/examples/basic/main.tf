# Runner VMSS wired to a vnet (runner subnet) and acr (AcrPull + login). Doubles
# as the CI plan/validate fixture. temporal_host is the reserved internal address
# the Temporal load balancer is pinned to. Omit acr_* when images are public.

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "vnet" {
  source = "../../../vnet"

  namespace           = "acme"
  environment         = "play"
  name                = "autoheal"
  resource_group_name = "rg-autoheal-play"
  location            = "centralus"
}

module "acr" {
  source = "../../../acr"

  namespace           = "acme"
  environment         = "play"
  name                = "autoheal"
  resource_group_name = "rg-autoheal-play"
  location            = "centralus"
}

module "runner" {
  source = "../../"

  namespace   = "acme"
  environment = "play"
  name        = "autoheal"
  attributes  = ["runner"]

  resource_group_name = "rg-autoheal-play"
  location            = "centralus"

  subnet_id        = module.vnet.subnet_runner_id
  acr_pull_enabled = true
  acr_id           = module.acr.acr_id
  acr_name         = module.acr.acr_name

  temporal_host              = "10.60.0.7:7233"
  tool_response_callback_url = "http://10.60.0.7:8083/api/v1/internal/sandbox-tool-responses"
  runner_image               = "${module.acr.login_server}/release/runner-go:latest"
  sandbox_image              = "${module.acr.login_server}/dev/sandbox:latest"

  admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAM example"
}

output "runner_vmss_id" {
  value = module.runner.vmss_id
}
