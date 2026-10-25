# Inputs for the runner composition. examples/azure/split/runner/terragrunt.hcl
# shows a typical set. The runner reaches the cluster only through
# temporal_address; nothing here reads the cluster.

# ---------------------------------------------------------------------------
# Naming and placement
# ---------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Customer or tenant, e.g. 'acme'. First element of every resource name. Use the namespace of compositions/azure."
}

variable "environment" {
  type        = string
  description = "Lifecycle, e.g. prod, staging, play. Not the region."
}

variable "name" {
  type        = string
  default     = "autoheal"
  description = "Component name; the middle element of resource names. Resources get a -runner suffix."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto every resource we create."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription for the runner, usually the subscription_id of compositions/azure. Everything we create goes here, and existing_subnet_id must be in it. Get it with: az account show --query id -o tsv"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription GUID. Get it with: az account show --query id -o tsv"
  }
}

variable "location" {
  type        = string
  description = "Azure region, e.g. centralus. With existing_subnet_id, the subnet's region."
}

variable "resource_group_name" {
  type        = string
  default     = ""
  description = "Resource group to create for the runner. Empty means 'rg-<namespace>-<environment>-<name>-runner'. Ignored when existing_resource_group_id is set."
}

variable "existing_resource_group_id" {
  type        = string
  default     = ""
  description = "Resource ID of a resource group in subscription_id to put the runner in, for organizations that do not let the deployer create resource groups. Empty means we create one."

  validation {
    condition     = var.existing_resource_group_id == "" || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.existing_resource_group_id))
    error_message = "existing_resource_group_id must look like /subscriptions/<id>/resourceGroups/<name>."
  }
}

# ---------------------------------------------------------------------------
# Where the runner connects
# ---------------------------------------------------------------------------

variable "temporal_address" {
  type        = string
  description = "Where the runner reaches Temporal, as <host>:<port>. Through the edge: the chart's runner host on 443 (global.edge.runner.host), e.g. runner.autoheal.acme.example:443. Through the chart's runner load balancers: their private IPv4 address on 7233, with temporal_tls = false."

  validation {
    condition = (
      can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?:[0-9]{1,5}$", var.temporal_address)) &&
      try(tonumber(split(":", var.temporal_address)[1]) >= 1 && tonumber(split(":", var.temporal_address)[1]) <= 65535, false)
    )
    error_message = "temporal_address must be <host>:<port>, such as runner.autoheal.acme.example:443."
  }
}

variable "temporal_tls" {
  type        = bool
  default     = true
  description = "Dial Temporal over TLS. True through the edge, where the chart's proxy checks temporal_token. False only for the chart's runner load balancers on a private route, where Temporal has no TLS and no key: temporal_address must then be a private IPv4 address."
}

variable "temporal_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "The runner key: the runner_token output of compositions/azure, the vault entry runner-token. The runner sends it with each call and the chart's proxy refuses calls without it. Required with temporal_tls; empty without. It is in the VMs' custom data, which Azure never returns on read, and in this state."

  validation {
    condition     = var.temporal_token == "" || can(regex("^[A-Za-z0-9]{32,}$", var.temporal_token))
    error_message = "temporal_token must be letters and digits, at least 32 of them: the runner_token output of compositions/azure."
  }
}

variable "temporal_server_name" {
  type        = string
  default     = ""
  description = "Name the runner checks in the edge certificate. Empty means the host of temporal_address. Set it only when the runner dials an address the certificate does not name."

  validation {
    condition     = var.temporal_server_name == "" || can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", var.temporal_server_name))
    error_message = "temporal_server_name must be empty or a host name, such as runner.autoheal.acme.example."
  }
}

variable "temporal_ca_certificate" {
  type        = string
  default     = ""
  description = "PEM of the CA that signed the edge certificate, when it is a private CA: the edge_ca_certificate of compositions/azure. The runner trusts it in addition to the public CAs. Empty when a public CA signed it."

  validation {
    condition     = var.temporal_ca_certificate == "" || can(regex("-----BEGIN CERTIFICATE-----", var.temporal_ca_certificate))
    error_message = "temporal_ca_certificate must be empty or a PEM certificate."
  }
}

variable "tool_response_url" {
  type        = string
  default     = ""
  description = "URL the runner posts sandbox tool results to, set as SANDBOX_TOOL_RESPONSE_CALLBACK_URL. Empty, the default, sends tool results through Temporal, so the runner needs nothing but temporal_address. With the chart's runner load balancers it may be http://<address>:8083/api/v1/internal/sandbox-tool-responses. An http:// URL must be a private IPv4 address; https:// may be any host."

  validation {
    condition     = var.tool_response_url == "" || can(regex("^https?://[^\\s/:]+(:[0-9]{1,5})?(/[^\\s]*)?$", var.tool_response_url))
    error_message = "tool_response_url must be empty or an http(s) URL."
  }
}

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------

variable "chart_version" {
  type        = string
  description = "Autoheal chart version that compositions/app installs, e.g. 1.0.0 (chart_version in versions.hcl in the examples). The runner pulls runner-go:chart-<chart_version> unless runner_image_tag is set, so bump it with the chart."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.chart_version))
    error_message = "chart_version must be a semantic version such as 1.0.0 or 1.1.0-rc.1."
  }
}

variable "runner_image" {
  type        = string
  default     = "public.ecr.aws/e4h3h0d9/app/runner-go"
  description = "Repository the runner VMs pull runner-go from, without a tag. The default is the public registry. For a registry you copy the images into, such as acmeprodautoheal.azurecr.io/app/runner-go, also set acr_id. The VMs retry the pull until the image exists, so it may be pushed after the apply."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/:-]*$", var.runner_image)) && !can(regex("@|:[^/]*$", var.runner_image))
    error_message = "runner_image must be a repository without a tag or digest, such as public.ecr.aws/e4h3h0d9/app/runner-go. Set the tag with runner_image_tag."
  }
}

variable "runner_image_tag" {
  type        = string
  default     = ""
  description = "Tag of the runner-go image. Empty means chart-<chart_version>. Changing it rolls the runner VMs."

  validation {
    condition     = can(regex("^([A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?$", var.runner_image_tag))
    error_message = "runner_image_tag must be a valid image tag, or empty."
  }
}

variable "sandbox_image" {
  type        = string
  default     = ""
  description = "Fully qualified sandbox image the runner VMs pre-pull at boot. Empty skips the pre-pull."

  validation {
    condition     = var.sandbox_image == "" || can(regex("^[A-Za-z0-9][A-Za-z0-9._/:@-]*$", var.sandbox_image))
    error_message = "sandbox_image must be empty or one image reference, such as public.ecr.aws/e4h3h0d9/app/sandbox:1.2.3, with no spaces."
  }
}

variable "acr_id" {
  type        = string
  default     = ""
  description = "Resource ID of an Azure Container Registry the runner pulls from: the registry of global.imageRegistry when you copy the images into your own. The runner identity gets AcrPull on it, and the VMs log in to it for the runner image and the sandbox images, even when runner_image is public. Empty means the images are public and no login runs."

  validation {
    condition     = var.acr_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ContainerRegistry/registries/[^/]+$", var.acr_id))
    error_message = "acr_id must be the resource ID of a Microsoft.ContainerRegistry/registries resource."
  }
}

variable "create_role_assignments" {
  type        = bool
  default     = true
  description = "Grant the runner identity AcrPull on acr_id. Set false when the deployer cannot grant roles: the required_role_assignments output then lists the grant for an administrator, and the VMs retry the pull until it exists."
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "existing_subnet_id" {
  type        = string
  default     = ""
  description = "Resource ID of a subnet for the runner VMs, in subscription_id, that already has a route to temporal_address and outbound access to the image registry, the git hosts and the endpoints the tools call. Empty means we create a VNet from address_space with the subnet snet-runner and a NAT gateway."

  validation {
    condition     = var.existing_subnet_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.existing_subnet_id))
    error_message = "existing_subnet_id must look like /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

variable "address_space" {
  type        = string
  default     = "10.61.0.0/24"
  description = "Address range of the VNet we create, all of it for snet-runner. When the VNet is connected to the edge's network, it must not overlap that network or anything connected to it. Ignored when existing_subnet_id is set."

  validation {
    condition = (
      can(cidrhost(var.address_space, 0)) &&
      try(cidrsubnet(var.address_space, 0, 0) == var.address_space, false) &&
      try(tonumber(split("/", var.address_space)[1]) >= 8 && tonumber(split("/", var.address_space)[1]) <= 28, false)
    )
    error_message = "address_space must be an IPv4 network address with a prefix between /8 and /28, such as 10.61.0.0/24."
  }
}

# ---------------------------------------------------------------------------
# Runner VMs
# ---------------------------------------------------------------------------

variable "vm_size" {
  type        = string
  default     = "Standard_D4s_v6"
  description = "VM size of the runner VMs. It must support accelerated networking."
}

variable "instance_count" {
  type        = number
  default     = 1
  description = "Number of runner VMs. Each is an independent Temporal worker."
}

variable "os_disk_size_gb" {
  type        = number
  default     = 1024
  description = "OS disk size of the runner VMs in GiB. Premium SSD speed grows with size: 1024 GiB (P30, 5000 IOPS) is the smallest size at least as fast as the disk of Autoheal's hosted runners. A smaller disk makes the first chat after a boot wait on disk writes."
}

variable "max_concurrent_activities" {
  type        = number
  default     = 20
  description = "Activities each runner VM runs at once. 20 matches Autoheal's hosted runners on the default 4 vCPU, 16 GiB size."
}

variable "admin_ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key for the runner VMs' admin user. Empty means we generate a key pair; the private key is kept only in the Terraform state (tls_private_key.runner)."
}
