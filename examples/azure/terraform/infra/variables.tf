# Set by the pipeline as TF_VAR_<name>, so they are not in this folder.

variable "autoheal_version" {
  type        = string
  description = "Autoheal chart version. The runner VMs pull app/runner-go:chart-<version>. Keep it equal to the app folder's."
}

# Secrets, from your pipeline's secret store. Terraform writes them to Key
# Vault. Add the others you use the same way (sso_client_secret,
# tls_certificate, llm_gateway_api_key, ...): examples/azure/README.md lists
# them.

variable "llm_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "LLM provider API key, stored in Key Vault as llm-api-key. Empty when the chart's LLM gateway is on."
}
