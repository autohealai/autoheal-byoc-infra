variable "cluster" {
  type = object({
    cloud          = string
    name           = string
    endpoint       = string
    ca_certificate = string
    resource_group = optional(string, "")
    region         = optional(string, "")
  })
  description = "The cluster output of the infra composition: cloud (azure or aws), name, API endpoint, base64 CA certificate, and resource_group (Azure) or region (AWS)."

  validation {
    condition     = contains(["azure", "aws"], var.cluster.cloud)
    error_message = "cluster.cloud must be azure or aws."
  }

  validation {
    condition     = var.cluster.cloud != "aws" || var.cluster.region != ""
    error_message = "cluster.region is required on AWS: aws eks get-token needs it."
  }
}

variable "infra_values" {
  type        = any
  description = "The autoheal_values output of the infra composition. Passed to the chart first, so values-customer.yaml cannot override what it does not set."
}

variable "customer_values" {
  type        = string
  default     = ""
  description = "Contents of values-customer.yaml, e.g. file(\"values-customer.yaml\"). Merged after infra_values, like a second -f flag. Must not set global.infra; the chart rejects it."
}

variable "chart_version" {
  type        = string
  description = "Autoheal chart version, e.g. 1.0.0. Every service, Temporal, Zitadel, the proxy and runner-go share it. Keep it equal to autoheal_version in the infra folder (versions.hcl in the examples)."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.chart_version))
    error_message = "chart_version must be a semantic version such as 1.0.0 or 1.1.0-rc.1."
  }
}

variable "chart_repository" {
  type        = string
  default     = "oci://public.ecr.aws/e4h3h0d9/charts"
  description = "Where the chart comes from: an OCI or HTTPS chart repository (the chart named autoheal in it), or a local path to the chart directory or packaged .tgz for testing a chart that is not published."
}

variable "namespace" {
  type        = string
  default     = "autoheal"
  description = "Kubernetes namespace for the release. Created when missing. Must match service_accounts.namespace in the infra folder, where the workload identities are federated."
}

variable "release_name" {
  type        = string
  default     = "autoheal"
  description = "Helm release name."
}

variable "kubelogin_login_mode" {
  type        = string
  default     = "azurecli"
  description = "kubelogin --login mode on AKS: azurecli, workloadidentity, spn, msi or devicecode. Ignored on AWS."

  validation {
    condition     = contains(["azurecli", "workloadidentity", "spn", "msi", "devicecode", "interactive"], var.kubelogin_login_mode)
    error_message = "kubelogin_login_mode must be azurecli, workloadidentity, spn, msi, devicecode or interactive."
  }
}

variable "timeout" {
  type        = number
  default     = 1200
  description = "Seconds Helm waits for the release to become ready before it rolls back."
}
