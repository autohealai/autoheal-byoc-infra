# Runner VMSS wired to a runner subnet and acr (AcrPull + login). Doubles as the
# CI plan/validate fixture. temporal_host is the chart's runner host on 443,
# reached through the edge over TLS with the runner key. Omit acr_* when images
# are public. The subnet needs outbound access (compositions/azure-runner adds a
# NAT gateway); this fixture leaves it out.

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

# The runner key: the runner_token output of compositions/azure.
variable "runner_token" {
  type      = string
  sensitive = true
  default   = ""
}

module "vnet" {
  source = "../../../vnet"

  namespace           = "acme"
  environment         = "play"
  name                = "autoheal"
  resource_group_name = "rg-autoheal-play"
  location            = "centralus"
}

resource "azurerm_subnet" "runner" {
  name                 = "snet-runner"
  resource_group_name  = "rg-autoheal-play"
  virtual_network_name = module.vnet.vnet_name
  address_prefixes     = ["10.60.18.0/24"]
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

  subnet_id        = azurerm_subnet.runner.id
  acr_pull_enabled = true
  acr_id           = module.acr.acr_id
  acr_name         = module.acr.acr_name

  temporal_host  = "runner.autoheal.acme.example:443"
  temporal_token = var.runner_token
  runner_image   = "${module.acr.login_server}/release/runner-go:latest"
  sandbox_image  = "${module.acr.login_server}/dev/sandbox:latest"

  admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAM example"
}

output "runner_vmss_id" {
  value = module.runner.vmss_id
}
