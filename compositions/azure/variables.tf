# Inputs for the Azure composition. examples/azure/prod/infra/terragrunt.hcl
# shows a typical set. Every building block takes an optional existing_* ID: set
# it to use a resource you already have, leave it empty and we create one.

# ---------------------------------------------------------------------------
# Naming and placement
# ---------------------------------------------------------------------------

variable "namespace" {
  type        = string
  description = "Customer or tenant, e.g. 'acme'. First element of every resource name."
}

variable "environment" {
  type        = string
  description = "Lifecycle, e.g. prod, staging, play. Not the region."
}

variable "name" {
  type        = string
  default     = "autoheal"
  description = "Component name; the middle element of resource names."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto every resource we create."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription to deploy into. Everything we create goes here, also when existing_aks_cluster_id is in another subscription. Get it with: az account show --query id -o tsv"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription GUID. Get it with: az account show --query id -o tsv"
  }
}

variable "location" {
  type        = string
  description = "Azure region, e.g. centralus. The region is not part of resource names."
}

variable "resource_group_name" {
  type        = string
  default     = ""
  description = "Resource group to create for the resources we own. Empty means 'rg-<namespace>-<environment>-<name>'. Ignored when existing_resource_group_id is set."
}

variable "existing_resource_group_id" {
  type        = string
  default     = ""
  description = "Resource ID of a resource group to put our resources in, for organizations that do not let the deployer create resource groups. Empty means we create one."

  validation {
    condition     = var.existing_resource_group_id == "" || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.existing_resource_group_id))
    error_message = "existing_resource_group_id must look like /subscriptions/<id>/resourceGroups/<name>."
  }
}

# ---------------------------------------------------------------------------
# Hostnames and edge
# ---------------------------------------------------------------------------

variable "hostname" {
  type        = string
  description = "The name users open, e.g. autoheal.acme.example."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.hostname))
    error_message = "hostname must be a lowercase DNS name such as autoheal.acme.example."
  }
}

variable "auth_hostname" {
  type        = string
  default     = ""
  description = "Login hostname. Empty means auth.<hostname>."
}

variable "auth_app_hostname" {
  type        = string
  default     = ""
  description = "auth-app hostname. Empty means auth-app.<hostname>."
}

variable "edge_mode" {
  type        = string
  default     = "loadbalancer"
  description = "How traffic reaches the Autoheal proxy: loadbalancer (a load balancer on the reserved proxy address; see edge_exposure), gateway-api, istio, ingress or none. Becomes global.edge.mode."

  validation {
    condition     = contains(["loadbalancer", "gateway-api", "istio", "ingress", "none"], var.edge_mode)
    error_message = "edge_mode must be one of loadbalancer, gateway-api, istio, ingress, none."
  }
}

variable "edge_exposure" {
  type        = string
  default     = "internal"
  description = "Where the proxy's load balancer listens in loadbalancer mode: internal, on existing_network.proxy_ip in the AKS subnet, or public, on existing_network.proxy_ip as a Standard static public IP in the cluster's node resource group, for users and webhooks from the internet. Public needs a brought cluster. On cluster_network_path = public, proxy_ip may be temporal_ip, so that one IP serves both. Becomes global.edge.exposure."

  validation {
    condition     = contains(["internal", "public"], var.edge_exposure)
    error_message = "edge_exposure must be internal or public."
  }
}

variable "edge_address" {
  type        = string
  default     = ""
  description = "IPv4 address of the customer's gateway, Istio ingress or Ingress controller. The DNS records point here when edge_mode is not loadbalancer. Empty means the records are left to the customer."

  validation {
    condition     = var.edge_address == "" || can(cidrhost("${var.edge_address}/32", 0))
    error_message = "edge_address must be an IPv4 address such as 10.50.0.20."
  }
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

variable "existing_dns_zone_id" {
  type        = string
  default     = ""
  description = "Resource ID of the Azure DNS zone (public or private) that holds the hostnames. We create A records in it, never the zone."

  validation {
    condition     = var.existing_dns_zone_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/(dnszones|privateDnsZones)/[^/]+$", var.existing_dns_zone_id))
    error_message = "existing_dns_zone_id must be the resource ID of a Microsoft.Network/dnszones or privateDnsZones resource."
  }
}

variable "create_dns_records" {
  type        = bool
  default     = true
  description = "Create A records for the three hostnames in existing_dns_zone_id. Set false when DNS is managed outside Azure; the required_dns_records output then lists the records to create."
}

variable "dns_record_ttl" {
  type        = number
  default     = 300
  description = "TTL in seconds for the A records."
}

# ---------------------------------------------------------------------------
# Versions and images
# ---------------------------------------------------------------------------

variable "autoheal_version" {
  type        = string
  description = "Autoheal release (the chart version). The runner VMs pull app/runner-go:chart-<autoheal_version> unless runner_image_tag is set."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.-]+)?$", var.autoheal_version))
    error_message = "autoheal_version must be a release version such as 1.0.0."
  }
}

variable "runner_image_repository" {
  type        = string
  default     = ""
  description = "Repository the runner VMs pull runner-go from. Empty means <registry>/app/runner-go: the composition's ACR when there is one, else public.ecr.aws/e4h3h0d9. Override to use another mirror or a test registry. The VMs retry the pull until the image exists, so it may be pushed after the apply."
}

variable "runner_image_tag" {
  type        = string
  default     = ""
  description = "Tag of the runner-go image. Empty means chart-<autoheal_version>. Changing it rolls the runner VMs."

  validation {
    condition     = can(regex("^([A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?$", var.runner_image_tag))
    error_message = "runner_image_tag must be a valid image tag, or empty."
  }
}

variable "runner_sandbox_image" {
  type        = string
  default     = ""
  description = "Fully qualified sandbox image the runner VMs pre-pull at boot. Empty skips the pre-pull."
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "network_cidr" {
  type        = string
  default     = "10.60.0.0/16"
  description = "Address space of the network we create. Subnets: AKS = first /4 split, Postgres, private endpoints and runner = /8 splits 16, 17 and 19. Ignored when existing_network is set, except for a cluster in another subscription with no runner, Postgres or endpoint subnet given: we then create a VNet in subscription_id from this range with those three subnets and no AKS subnet. It must not overlap the cluster's VNet."

  validation {
    condition     = can(cidrhost(var.network_cidr, 0)) && tonumber(split("/", var.network_cidr)[1]) >= 8 && tonumber(split("/", var.network_cidr)[1]) <= 20
    error_message = "network_cidr must be an IPv4 CIDR with a prefix between /8 and /20, such as 10.60.0.0/16."
  }
}

variable "existing_network" {
  type = object({
    aks_subnet_id      = string
    runner_subnet_id   = optional(string, "")
    temporal_ip        = string
    proxy_ip           = optional(string, "")
    postgres_subnet_id = optional(string, "")
    endpoint_subnet_id = optional(string, "")
    # Private DNS zone for a Postgres server we create in this network, already
    # linked to the VNet. Empty means we create one and link it.
    postgres_private_dns_zone_id = optional(string, "")
    # privatelink zones for the private endpoints we create, keyed blob, vault and
    # redis. A missing key means we create that zone and link it to the VNet.
    private_dns_zone_ids = optional(map(string), {})
  })
  default     = null
  description = "A network you already have. temporal_ip, and proxy_ip in loadbalancer mode, are free addresses in the AKS subnet that the chart pins its internal load balancers to; with cluster_network_path = public, temporal_ip is instead a Standard static public IP in the cluster's node resource group (unless runner_temporal_address is set), and with edge_exposure = public, so is proxy_ip. runner_subnet_id is required; postgres_subnet_id is needed only when we create Postgres; endpoint_subnet_id only when we create Redis or private endpoints. The AKS subnet is in the cluster's subscription; the other subnets must be in subscription_id. For a cluster in another subscription, leave the other three empty and we create a VNet for them from network_cidr. Null means we create the network."

  validation {
    condition = var.existing_network == null ? true : alltrue([
      for id in compact([
        var.existing_network.aks_subnet_id,
        var.existing_network.runner_subnet_id,
        var.existing_network.postgres_subnet_id,
        var.existing_network.endpoint_subnet_id,
      ]) : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", id))
    ])
    error_message = "Every subnet ID in existing_network must look like /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }

  validation {
    condition = var.existing_network == null ? true : alltrue([
      for ip in compact([var.existing_network.temporal_ip, var.existing_network.proxy_ip]) : can(cidrhost("${ip}/32", 0))
    ])
    error_message = "existing_network.temporal_ip and proxy_ip must be IPv4 addresses such as 10.20.4.11."
  }
}

variable "cluster_vnet_dns_link_enabled" {
  type        = bool
  default     = false
  description = "For a cluster in another subscription: also link the private DNS zones we create (Postgres and privatelink) to the cluster's VNet, so pods resolve them. The links are created in our resource group; the deployer needs Microsoft.Network/virtualNetworks/join/action on the cluster's VNet. Leave false when the cluster's VNet resolves them through central DNS. Ignored otherwise."
}

variable "cluster_network_path" {
  type        = string
  default     = "private"
  description = "For a cluster in another subscription: how pods and runner VMs reach each other's subscription. private: the customer connects the two VNets (peering or a hub) and every service is reached through private endpoints. public: no VNet connection; Postgres and the Key Vaults allow only workload_egress_ip_ranges, storage allows the cluster's AKS subnet, Redis is public with its access key and TLS, and compositions/app exposes Temporal and the tool-response listener on existing_network.temporal_ip (a static public IP) to the runner's NAT address only, or, with runner_temporal_address, the customer's firewall forwards them to existing_network.temporal_ip (a private address). Fixed at create time for Postgres."

  validation {
    condition     = contains(["private", "public"], var.cluster_network_path)
    error_message = "cluster_network_path must be private or public."
  }
}

variable "runner_temporal_address" {
  type        = string
  default     = ""
  description = "DNS name or IPv4 address the runner VMs connect to for Temporal (TCP 7233) and the tool-response listener (TCP 8083). Empty means the Temporal address (existing_network.temporal_ip, or the reserved address in a network we create). Set it when the runners reach Temporal by a name, such as a private DNS record for temporal_ip. With cluster_network_path = public it also means your firewall forwards both ports from this address to existing_network.temporal_ip, a free private address in the AKS subnet: the chart keeps its internal load balancers there and no public load balancer is created. A name or address only, without a scheme, port or path."

  validation {
    condition = var.runner_temporal_address == "" || (
      length(var.runner_temporal_address) <= 253 &&
      can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$", var.runner_temporal_address))
    )
    error_message = "runner_temporal_address must be a DNS name such as temporal.autoheal.acme.example or an IPv4 address, without a scheme, port or path."
  }
}

variable "private_endpoints_enabled" {
  type        = bool
  default     = false
  description = "Create private endpoints for the Blob account and Key Vault we create. This is the recommended runtime path for in-cluster pods. When false, the runtime path relies on workload_egress_ip_ranges or an Allow default action. Redis we create always has a private endpoint."
}

variable "deployer_ip_ranges" {
  type        = list(string)
  default     = []
  description = "Apply-time path. Public egress CIDRs of the Terraform apply host, allowed through the Blob and Key Vault firewalls we create so the apply can write vault entries. A single address may be written with or without /32. Leave empty only when both *_network_default_action values are Allow."
}

variable "workload_egress_ip_ranges" {
  type        = list(string)
  default     = []
  description = "Runtime path without private endpoints. Public outbound CIDRs of the AKS cluster, allowed through the Blob and Key Vault firewalls we create, and through the Postgres firewall with cluster_network_path = public. Prefer private_endpoints_enabled = true."
}

variable "storage_network_default_action" {
  type        = string
  default     = "Deny"
  description = "Firewall default action of the storage account we create. Deny is recommended; Allow only for throwaway installs."

  validation {
    condition     = contains(["Allow", "Deny"], var.storage_network_default_action)
    error_message = "storage_network_default_action must be exactly \"Allow\" or \"Deny\"."
  }
}

variable "key_vault_network_default_action" {
  type        = string
  default     = "Deny"
  description = "Firewall default action of the Key Vault we create. Deny is recommended; Allow only for throwaway installs."

  validation {
    condition     = contains(["Allow", "Deny"], var.key_vault_network_default_action)
    error_message = "key_vault_network_default_action must be exactly \"Allow\" or \"Deny\"."
  }
}

# ---------------------------------------------------------------------------
# Brought resources. One ID per block; we read the rest from it.
# ---------------------------------------------------------------------------

variable "existing_aks_cluster_id" {
  type        = string
  default     = ""
  description = "Resource ID of an AKS cluster you already have. It must have the OIDC issuer and workload identity on, and run the Secrets Store CSI driver with the Azure Key Vault provider (the AKS add-on azure-keyvault-secrets-provider, or your own install). Needs existing_network. It may be in another subscription of the same Entra tenant: we then only read it and its AKS subnet there, and create nothing in that subscription."

  validation {
    condition     = var.existing_aks_cluster_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ContainerService/managedClusters/[^/]+$", var.existing_aks_cluster_id))
    error_message = "existing_aks_cluster_id must be the resource ID of a Microsoft.ContainerService/managedClusters resource."
  }
}

variable "existing_postgres_id" {
  type        = string
  default     = ""
  description = "Resource ID of a PostgreSQL Flexible Server you already have (version 15 or later). Its admin password must be passed as postgres_admin_password."

  validation {
    condition     = var.existing_postgres_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.DBforPostgreSQL/flexibleServers/[^/]+$", var.existing_postgres_id))
    error_message = "existing_postgres_id must be the resource ID of a Microsoft.DBforPostgreSQL/flexibleServers resource."
  }
}

variable "existing_redis_id" {
  type        = string
  default     = ""
  description = "Resource ID of an Azure Managed Redis (Microsoft.Cache/redisEnterprise) or Azure Cache for Redis (Microsoft.Cache/redis) you already have. Access keys must be enabled."

  validation {
    condition     = var.existing_redis_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Cache/(redisEnterprise|redis)/[^/]+$", var.existing_redis_id))
    error_message = "existing_redis_id must be the resource ID of a Microsoft.Cache/redisEnterprise or Microsoft.Cache/redis resource."
  }
}

variable "existing_storage_account_id" {
  type        = string
  default     = ""
  description = "Resource ID of a storage account you already have. It must have a flat namespace (hierarchical namespace off) and blob versioning on."

  validation {
    condition     = var.existing_storage_account_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Storage/storageAccounts/[^/]+$", var.existing_storage_account_id))
    error_message = "existing_storage_account_id must be the resource ID of a Microsoft.Storage/storageAccounts resource."
  }
}

variable "existing_acr_id" {
  type        = string
  default     = ""
  description = "Resource ID of an Azure Container Registry you already have, for installs that mirror images. It must hold the images under app/ and external/, the chart's layout. Empty and create_registry = false means images come from the public registry."

  validation {
    condition     = var.existing_acr_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ContainerRegistry/registries/[^/]+$", var.existing_acr_id))
    error_message = "existing_acr_id must be the resource ID of a Microsoft.ContainerRegistry/registries resource."
  }
}

variable "existing_key_vault_id" {
  type        = string
  default     = ""
  description = "Resource ID of a Key Vault you already have. It must use Azure RBAC authorization."

  validation {
    condition     = var.existing_key_vault_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.KeyVault/vaults/[^/]+$", var.existing_key_vault_id))
    error_message = "existing_key_vault_id must be the resource ID of a Microsoft.KeyVault/vaults resource."
  }
}

variable "existing_runtime_key_vault_id" {
  type        = string
  default     = ""
  description = "Resource ID of a Key Vault you already have for the runtime vault, where api-server-go stores the integration credentials users enter. It must use Azure RBAC authorization and must be a different vault from the install vault."

  validation {
    condition     = var.existing_runtime_key_vault_id == "" || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.KeyVault/vaults/[^/]+$", var.existing_runtime_key_vault_id))
    error_message = "existing_runtime_key_vault_id must be the resource ID of a Microsoft.KeyVault/vaults resource."
  }
}

variable "create_registry" {
  type        = bool
  default     = false
  description = "Create an Azure Container Registry. Off by default because images come from the public registry. With a registry, autoheal_values points the chart's images at it and the runner pulls from it, so copy the images into it (app/ and external/) before installing the chart. v1 installs set true to keep their registry. Ignored when existing_acr_id is set."
}

variable "redis_enabled" {
  type        = bool
  default     = true
  description = "Use Redis. When true and existing_redis_id is empty, we create an Azure Managed Redis with a private endpoint. When false, global.infra.redis and the Redis vault entries are left out; the current chart version requires Redis, so keep true for a chart install."
}

variable "create_storage_container" {
  type        = bool
  default     = true
  description = "Create the blob container in a brought storage account. Set false when the container already exists. A storage account we create always gets the container."
}

variable "storage_container_name" {
  type        = string
  default     = "autoheal"
  description = "Blob container Autoheal uses. v1 installs set \"attachments\" to keep their container: changing the name replaces it."
}

# ---------------------------------------------------------------------------
# Role assignments
# ---------------------------------------------------------------------------

variable "create_role_assignments" {
  type        = bool
  default     = true
  description = "Create the role grants Autoheal needs. Set false when the deployer cannot grant roles: no grants are made, the required_role_assignments output lists them for an administrator, and the apply stops while any are missing."
}

variable "service_accounts" {
  type = object({
    namespace     = optional(string, "autoheal")
    secrets       = optional(list(string), ["autoheal-hooks"])
    api_server    = optional(list(string), ["api-server-go"])
    agents_worker = optional(list(string), ["agents-py-http", "agents-py-worker"])
  })
  default     = {}
  description = "Chart service accounts federated to each workload identity. secrets: the pods that read the vault, which in the chart is only autoheal-hooks (the secrets-sync hook Job and CronJob); no service pod mounts the vault. api_server and agents_worker: pods that read and write the blob container. Defaults match the chart in namespace autoheal."
}

# ---------------------------------------------------------------------------
# Sizing
# ---------------------------------------------------------------------------

variable "aks_node_size" {
  type        = string
  default     = "Standard_D4s_v6"
  description = "VM size of the AKS system node pool we create."
}

variable "aks_node_count" {
  type        = number
  default     = 2
  description = "Minimum node count of the AKS node pool we create (autoscaler floor)."
}

variable "aks_node_max_count" {
  type        = number
  default     = 4
  description = "Maximum node count of the AKS node pool we create. Raised to aks_node_count when lower."
}

variable "postgres_sku" {
  type        = string
  default     = "GP_Standard_D2ds_v5"
  description = "SKU of the PostgreSQL Flexible Server we create. Use GP_ or MO_ for a real install."
}

variable "postgres_version" {
  type        = string
  default     = "16"
  description = "Major version of the PostgreSQL Flexible Server we create."
}

variable "postgres_storage_mb" {
  type        = number
  default     = 32768
  description = "Storage of the PostgreSQL Flexible Server we create, in MB."
}

variable "postgres_admin_login" {
  type        = string
  default     = "pgadmin"
  description = "Admin login of the PostgreSQL Flexible Server we create. Fixed at create time. Ignored for a brought server, whose login is read from it."
}

variable "redis_sku" {
  type        = string
  default     = "Balanced_B0"
  description = "SKU of the Azure Managed Redis we create."
}

variable "redis_high_availability_enabled" {
  type        = bool
  default     = false
  description = "Replicate the Azure Managed Redis we create across zones."
}

variable "runner_node_count" {
  type        = number
  default     = 1
  description = "Number of runner VMs."
}

variable "runner_vm_size" {
  type        = string
  default     = "Standard_D4s_v6"
  description = "VM size of the runner VMs."
}

variable "runner_os_disk_size_gb" {
  type        = number
  default     = 1024
  description = "OS disk size of the runner VMs in GiB. Premium SSD speed grows with size: 1024 GiB (P30, 5000 IOPS) is the smallest size at least as fast as the disk of Autoheal's hosted runners. A smaller disk makes the first chat after a boot wait on disk writes."
}

variable "runner_max_concurrent_activities" {
  type        = number
  default     = 20
  description = "Activities each runner VM runs at once. 20 matches Autoheal's hosted runners on the default 4 vCPU, 16 GiB size."
}

variable "runner_admin_ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key for the runner VMs' admin user. Empty means we generate a key pair; the private key is kept only in the Terraform state (tls_private_key.runner), not in the vault."
}

# ---------------------------------------------------------------------------
# AKS access
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  type        = string
  default     = null
  description = "Version of the AKS cluster we create. null means the AKS default."
}

variable "admin_group_object_ids" {
  type        = list(string)
  default     = []
  description = "Entra group object IDs granted cluster admin on the AKS cluster we create. Setting any also disables the local admin accounts."
}

variable "aks_admin_tenant_id" {
  type        = string
  default     = ""
  description = "Entra tenant for AKS Entra integration. Empty means the deployer's tenant."
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the public API server of the AKS cluster we create. Empty means no restriction. Ignored when private_cluster_enabled = true."
}

variable "private_cluster_enabled" {
  type        = bool
  default     = false
  description = "Create a private AKS control plane with no public endpoint. The apply host and the app install must then have network access to the VNet and resolve the cluster's private DNS name."
}

variable "acr_sku" {
  type        = string
  default     = "Standard"
  description = "SKU of the Azure Container Registry we create: Basic, Standard or Premium."
}

# ---------------------------------------------------------------------------
# Key Vault, backup, high availability and encryption at rest
#
# Defaults keep v1 behaviour. Postgres geo-redundant backup, the customer-managed
# key, the Key Vault soft-delete window and purge protection are fixed at create
# time; decide them before the first apply.
# ---------------------------------------------------------------------------

variable "key_vault_purge_protection_enabled" {
  type        = bool
  default     = false
  description = "Enable purge protection on the Key Vault we create (irreversible). Required when cmk_enabled = true."
}

variable "key_vault_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Days a deleted vault or secret can be recovered (7-90). Fixed at create time. Recommended for production: 90."
}

variable "runtime_key_vault_purge_protection_enabled" {
  type        = bool
  default     = null
  nullable    = true
  description = "Enable purge protection on the runtime Key Vault we create (irreversible). null means the same as key_vault_purge_protection_enabled."
}

variable "runtime_key_vault_soft_delete_retention_days" {
  type        = number
  default     = 90
  description = "Days a deleted runtime vault or secret can be recovered (7-90). api-server-go recovers a deleted credential when the same one is saved again within this window. Fixed at create time."

  validation {
    condition     = var.runtime_key_vault_soft_delete_retention_days >= 7 && var.runtime_key_vault_soft_delete_retention_days <= 90
    error_message = "runtime_key_vault_soft_delete_retention_days must be between 7 and 90."
  }
}

variable "postgres_backup_retention_days" {
  type        = number
  default     = 7
  description = "Days of automatic Postgres backups to keep (1-35). Recommended for production: 35."
}

variable "postgres_geo_redundant_backup_enabled" {
  type        = bool
  default     = false
  description = "Copy Postgres backups to the paired region. Fixed at create time. Cannot be combined with cmk_enabled yet."
}

variable "postgres_auto_grow_enabled" {
  type        = bool
  default     = false
  description = "Let Postgres storage grow before it fills up. Strongly recommended for a real install."
}

variable "postgres_high_availability_enabled" {
  type        = bool
  default     = false
  description = "Run a zone-redundant Postgres standby. Needs a zonal region and a GP_ or MO_ SKU."
}

variable "postgres_delete_protection_enabled" {
  type        = bool
  default     = false
  description = "Lock the Postgres server against deletion. Recommended for production: true."
}

variable "blob_replication_type" {
  type        = string
  default     = "LRS"
  description = "Redundancy of the storage account we create: LRS, ZRS, GRS or GZRS."
}

variable "blob_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Days a deleted blob can be recovered (0 = off)."
}

variable "blob_container_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Days a deleted container can be recovered (0 = off)."
}

variable "blob_pitr_enabled" {
  type        = bool
  default     = false
  description = "Enable blob point-in-time restore."
}

variable "blob_restore_days" {
  type        = number
  default     = 6
  description = "How far back point-in-time restore can go, in days. Must be less than blob_soft_delete_retention_days."
}

variable "cmk_enabled" {
  type        = bool
  default     = false
  description = "Encrypt the Postgres server and storage account we create with a customer-managed key in the Key Vault we create. Needs key_vault_purge_protection_enabled = true and create_role_assignments = true. Fixed at create time on Postgres. Cannot be combined with postgres_geo_redundant_backup_enabled yet."
}

# ---------------------------------------------------------------------------
# Secrets. Pass these as TF_VAR_* pipeline secrets, never in a committed file.
# ---------------------------------------------------------------------------

variable "postgres_admin_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Admin password of a brought Postgres server (required with existing_postgres_id). Optional for a server we create; empty means we generate one. Stored in the vault as postgres-admin-password."
}

variable "llm_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "LLM provider API key. Stored in the vault as llm-api-key. Not needed for Bedrock, for Azure OpenAI with workload identity, or with the chart's LLM gateway on (global.llm.gateway), since the gateway holds the provider keys."
}

variable "llm_gateway_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Key of the customer's LLM gateway (global.llm.gateway in the chart), not a provider key. Stored in the vault as gateway-api-key, the chart's default for global.llm.gateway.apiKeyVaultEntry. Needed for every gateway kind except custom, as agents-py does not start without it. For a gateway that ignores it, such as Portkey OSS, set any value."
}

variable "llm_gateway_extra_headers" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Extra request headers for the LLM gateway, as a JSON object of strings with at least one header. Stored in the vault as gateway-extra-headers, and global.llm.gateway.extraHeadersVaultEntry is suggested in autoheal_values, with an empty apiKeyVaultEntry when llm_gateway_api_key is unset. For Portkey OSS it holds the x-portkey-config header, which carries the provider keys."

  validation {
    condition = var.llm_gateway_extra_headers == "" || try(
      length(jsondecode(var.llm_gateway_extra_headers)) > 0 &&
      alltrue([for v in values(jsondecode(var.llm_gateway_extra_headers)) : v != null && jsonencode(v) == jsonencode(tostring(v))]),
      false,
    )
    error_message = "llm_gateway_extra_headers must be a JSON object with at least one header, each value a string. Leave it empty for no headers."
  }
}

variable "sso_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Client secret of the customer's SSO application. Stored in the vault as sso-client-secret."
}

variable "tls_certificate" {
  type = object({
    certificate = string
    private_key = string
  })
  default     = null
  sensitive   = true
  description = "Corporate TLS certificate (PEM, full chain) and private key (PEM) for the three hostnames. Stored in the vault as tls-certificate and tls-private-key. Not needed with a cloud-issued or cert-manager certificate."
}

variable "edge_ca_certificate" {
  type        = string
  default     = ""
  description = "PEM certificate of the private CA that signed tls_certificate. Stored in the vault as edge-ca-certificate, and global.edge.tls.caVaultEntry is suggested in autoheal_values so api-server-go trusts it. Needed only when a private CA signed the edge certificate."

  validation {
    condition     = var.edge_ca_certificate == "" || startswith(trimspace(var.edge_ca_certificate), "-----BEGIN CERTIFICATE-----")
    error_message = "edge_ca_certificate must be a PEM certificate."
  }
}

variable "github_app_private_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Private key of the GitHub App, as PEM text. Stored base64-encoded in the vault as github-app-private-key, the form the chart reads. The chart reads it only when values-customer.yaml sets api-server-go.secretEnv.GITHUB_APP_PRIVATE_KEY_BASE64 to github-app-private-key."

  validation {
    condition     = var.github_app_private_key == "" || startswith(trimspace(var.github_app_private_key), "-----BEGIN")
    error_message = "github_app_private_key must be PEM text, not base64. Terraform encodes it."
  }
}

variable "github_app_webhook_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Webhook secret of the GitHub App. Stored in the vault as github-app-webhook-secret. The chart reads it only when values-customer.yaml sets api-server-go.secretEnv.GITHUB_APP_WEBHOOK_SECRET to github-app-webhook-secret."
}
