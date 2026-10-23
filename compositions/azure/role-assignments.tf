# Role grants. With create_role_assignments = true (the default) each module makes
# its own grants: the identities in identity.tf, the cluster identity and kubelet
# in modules/azure/aks, the deployer on the vault and the api-server identity on
# the runtime vault in keyvault.tf. The
# one grant made here is the deployer's access to a cluster we create, so the app
# folder can install the chart with kubelogin.
#
# With create_role_assignments = false no grant is made. required_grants below
# lists every grant Autoheal needs, the required_role_assignments output prints
# it for an administrator, and the apply checks that the workload grants exist
# and stops, naming the missing ones, while any are missing.
#
# Role definition GUIDs are Azure built-ins and the same in every tenant.

resource "azurerm_role_assignment" "deployer_aks" {
  count                = local.create_cluster && var.create_role_assignments ? 1 : 0
  scope                = module.aks[0].cluster_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

locals {
  role_guids = {
    key_vault_secrets_user        = "4633458b-17de-408a-b874-0445c86b69e6"
    key_vault_secrets_officer     = "b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
    storage_blob_data_contributor = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    acr_pull                      = "7f951dda-4ed3-4680-a7ca-43fe172d538d"
    network_contributor           = "4d97b98b-1d4f-4787-a291-c67834d212e7"
    aks_rbac_cluster_admin        = "b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b"
  }

  deployer_object_id = data.azurerm_client_config.current.object_id

  # The kubelet identity of a cluster we create. A brought cluster's is not read.
  kubelet_object_id = local.create_cluster ? module.aks[0].kubelet_identity_object_id : ""

  # Scope and display name of the cluster identity's network grant: the VNet we
  # create, or the AKS subnet of a brought network.
  cluster_network_scope = local.create_network ? try(module.vnet[0].vnet_id, "") : try(var.existing_network.aks_subnet_id, "")
  cluster_network_name = local.create_network ? try(module.vnet[0].vnet_name, "") : (
    local.create_cluster ? "${split("/", var.existing_network.aks_subnet_id)[8]}/${split("/", var.existing_network.aks_subnet_id)[10]}" : ""
  )

  # Every grant Autoheal needs. Keys and the conditions that pick them are
  # plan-time only. text is what an administrator reads; check marks the grants
  # the apply verifies. Deployer grants are listed but not checked: the deployer
  # may hold them through a group or a parent scope, and a missing one fails the
  # apply anyway with Azure's own error.
  required_grants = merge(
    {
      secrets-kv = {
        text         = "Key Vault Secrets User on ${local.key_vault_name} for ${module.secrets_identity.name}"
        role_guid    = local.role_guids.key_vault_secrets_user
        scope        = local.key_vault_id
        principal_id = module.secrets_identity.principal_id
        check        = true
      }
      api-server-blob = {
        text         = "Storage Blob Data Contributor on ${local.storage_account_name} for ${module.api_server_identity.name}"
        role_guid    = local.role_guids.storage_blob_data_contributor
        scope        = local.storage_account_id
        principal_id = module.api_server_identity.principal_id
        check        = true
      }
      api-server-runtime-kv = {
        text         = "Key Vault Secrets Officer on ${local.runtime_key_vault_name} for ${module.api_server_identity.name}"
        role_guid    = local.role_guids.key_vault_secrets_officer
        scope        = local.runtime_key_vault_id
        principal_id = module.api_server_identity.principal_id
        check        = true
      }
      agents-worker-blob = {
        text         = "Storage Blob Data Contributor on ${local.storage_account_name} for ${module.agents_worker_identity.name}"
        role_guid    = local.role_guids.storage_blob_data_contributor
        scope        = local.storage_account_id
        principal_id = module.agents_worker_identity.principal_id
        check        = true
      }
    },
    local.create_key_vault ? {
      deployer-kv = {
        text         = "Key Vault Secrets Officer on ${local.key_vault_name} for the deployer (object ID ${local.deployer_object_id})"
        role_guid    = local.role_guids.key_vault_secrets_officer
        scope        = local.key_vault_id
        principal_id = local.deployer_object_id
        check        = false
      }
    } : {},
    local.create_cluster ? {
      cluster-network = {
        text         = "Network Contributor on ${local.cluster_network_name} for ${module.aks[0].identity_name}"
        role_guid    = local.role_guids.network_contributor
        scope        = local.cluster_network_scope
        principal_id = module.aks[0].identity_principal_id
        check        = true
      }
      deployer-aks = {
        text         = "Azure Kubernetes Service RBAC Cluster Admin on ${local.cluster_name} for the deployer (object ID ${local.deployer_object_id})"
        role_guid    = local.role_guids.aks_rbac_cluster_admin
        scope        = local.cluster_id
        principal_id = local.deployer_object_id
        check        = false
      }
    } : {},
    # The nodes pull the chart's images from the registry. modules/azure/aks
    # makes this grant for a cluster we create; it is listed and checked like
    # the others when create_role_assignments = false. A brought cluster's
    # kubelet identity is not read, so its grant is in
    # required_cluster_owner_actions instead.
    local.acr_enabled && local.create_cluster ? {
      kubelet-acr = {
        text         = "AcrPull on ${local.acr_name} for the kubelet identity of ${local.cluster_name}"
        role_guid    = local.role_guids.acr_pull
        scope        = local.acr_id
        principal_id = local.kubelet_object_id
        check        = true
      }
    } : {},
  )

  # Display order of required_role_assignments.
  required_grant_order = ["secrets-kv", "api-server-blob", "api-server-runtime-kv", "agents-worker-blob", "deployer-kv", "cluster-network", "deployer-aks", "kubelet-acr"]

  checked_grants = var.create_role_assignments ? {} : {
    for k, g in local.required_grants : k => g if g.check
  }
}

# Assignments for each checked principal at its scope. The list includes grants
# at parent scopes, which also count.
data "azurerm_role_assignments" "required" {
  for_each     = local.checked_grants
  scope        = each.value.scope
  principal_id = each.value.principal_id
}

locals {
  # A grant is present when the principal holds the role at the scope or at a
  # parent of it (resource group, subscription, management group).
  missing_grants = [
    for k, g in local.checked_grants : g.text if length([
      for a in data.azurerm_role_assignments.required[k].role_assignments : a
      if endswith(lower(a.role_definition_id), g.role_guid) && (
        startswith(lower("${g.scope}/"), lower("${trimsuffix(a.role_assignment_scope, "/")}/")) ||
        startswith(lower(a.role_assignment_scope), "/providers/microsoft.management/managementgroups/")
      )
    ]) == 0
  ]
}

resource "terraform_data" "role_assignment_check" {
  count = var.create_role_assignments ? 0 : 1

  lifecycle {
    precondition {
      condition     = length(local.missing_grants) == 0
      error_message = "create_role_assignments = false and these role grants are missing: ${join("; ", local.missing_grants)}. An administrator must make them (the required_role_assignments output lists them all), then run the apply again."
    }
  }
}
