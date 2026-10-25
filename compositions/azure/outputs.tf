# Outputs for the app folder and for people. The AWS composition emits the same
# names in 2.x (docs/MODULE_STANDARD.md section 8).
#
#   autoheal_values            the chart's infra values, as an object
#   autoheal_values_yaml       the same values as YAML text (values-infra.yaml)
#   cluster                    what compositions/app needs to log in to the cluster;
#                              for a brought cluster compositions/azure-cluster
#                              outputs the full details instead
#   federation                 the identities a brought cluster must trust, for
#                              compositions/azure-cluster
#   required_role_assignments  grants an administrator must make, filled only when
#                              create_role_assignments = false
#   required_dns_records       records a person must create, filled only when we
#                              do not create them
#   required_cluster_owner_actions
#                              what the owner of a brought cluster must do, filled
#                              only for a brought cluster
#   network                    the VNet and subnets Autoheal runs in, created or
#                              brought
#   runner_token               the runner key, for compositions/azure-runner
#
# Only runner_token holds a secret, and it is marked sensitive.

output "autoheal_values" {
  description = "Infra values for the Autoheal chart (global.infra facts, suggestions, and the Temporal and Zitadel copies). Pass to compositions/app as infra_values."
  value       = local.autoheal_values
}

output "autoheal_values_yaml" {
  description = "autoheal_values as YAML, for customers who install with Helm or Flux and commit values-infra.yaml."
  value       = yamlencode(local.autoheal_values)
}

output "cluster" {
  description = "Cluster connection details for compositions/app: cloud, name, resource_group, subscription_id, endpoint and base64 ca_certificate. subscription_id is the cluster's, which differs from subscription_id for a brought cluster in another subscription. For a brought cluster endpoint and ca_certificate are empty, since the cluster is not read here: pass the cluster output of compositions/azure-cluster to compositions/app instead. Authentication is kubelogin with Entra ID; no credential is output."
  value = {
    cloud           = "azure"
    name            = local.cluster_name
    resource_group  = local.cluster_rg
    subscription_id = local.cluster_subscription_id
    endpoint        = local.cluster_endpoint
    ca_certificate  = local.cluster_ca_certificate
  }
}

output "required_role_assignments" {
  description = "Role grants an administrator must make, as readable lines. Filled only when create_role_assignments = false; the apply stops while a workload grant is missing."
  value = var.create_role_assignments ? [] : [
    for k in local.required_grant_order : local.required_grants[k].text if contains(keys(local.required_grants), k)
  ]
}

output "required_dns_records" {
  description = "DNS records a person must create (name, type, value). Filled when create_dns_records = false, or when the address is not known yet (edge_address empty in a mode other than loadbalancer)."
  value       = local.required_dns_records
}

output "required_cluster_owner_actions" {
  description = "What the owner of a brought cluster must do, as readable lines: the deployer's roles on the cluster, the namespace, the cluster features, AcrPull for the nodes when there is a registry and, for a cluster in another subscription, the network path and private DNS between the two VNets, or on the public path the storage network rule for the AKS subnet and the fixed outbound addresses. Filled only when existing_aks_cluster_id is set."
  value       = local.cluster_owner_actions
}

output "federation" {
  description = "Brought cluster only, else null: the input of compositions/azure-cluster. subscription_id, where the identities are, and per identity (secrets, api_server, agents_worker) its resource ID and the chart service accounts it trusts. compositions/azure-cluster federates each to the cluster's OIDC issuer. For a cluster we create the federation is made here."
  value = local.create_cluster ? null : {
    subscription_id = var.subscription_id
    identities = {
      secrets = {
        identity_id      = module.secrets_identity.identity_id
        service_accounts = local.federated_service_accounts.secrets
      }
      api_server = {
        identity_id      = module.api_server_identity.identity_id
        service_accounts = local.federated_service_accounts.api_server
      }
      agents_worker = {
        identity_id      = module.agents_worker_identity.identity_id
        service_accounts = local.federated_service_accounts.agents_worker
      }
    }
  }
}

output "network" {
  description = "The VNet and subnets Autoheal runs in: vnet_id, vnet_name, resource_group_name, address_space, cluster_vnet_id, aks_subnet_id and private_endpoint_subnet_id. vnet_* describe the VNet of Postgres and the private endpoints, empty on the public path; cluster_vnet_id is the AKS subnet's VNet, the same VNet unless the cluster is in another subscription. For a brought VNet address_space is empty, as the VNet is not read, and private_endpoint_subnet_id is empty when existing_network.endpoint_subnet_id is."
  value = {
    vnet_id                    = local.workload_vnet_id
    vnet_name                  = local.create_vnet ? module.vnet[0].vnet_name : try(split("/", local.workload_vnet_id)[8], "")
    resource_group_name        = local.create_vnet ? local.rg : try(split("/", local.workload_vnet_id)[4], "")
    address_space              = local.create_vnet ? [var.network_cidr] : []
    cluster_vnet_id            = local.create_network ? module.vnet[0].vnet_id : local.brought_vnet_id
    aks_subnet_id              = local.aks_subnet_id
    private_endpoint_subnet_id = local.endpoint_subnet_id
  }
}

output "runner_token" {
  description = "The runner key, also in the vault entry runner-token: the key a runner outside the cluster sends as TEMPORAL_TOKEN when the chart's global.edge.runner.host is set. Pass it to compositions/azure-runner as temporal_token. Sensitive: shown only with terraform output -raw runner_token."
  value       = random_password.runner_token.result
  sensitive   = true
}
