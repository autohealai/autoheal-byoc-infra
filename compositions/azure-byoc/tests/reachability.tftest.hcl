# Guards the Blob/Key Vault reachability preconditions on azurerm_resource_group.this
# in main.tf. `terraform validate` (the CI static gate) does not evaluate lifecycle
# preconditions; `terraform test` runs a real plan, which does. azurerm/random are
# mocked, so no subscription is touched.
#
# Both preconditions live on azurerm_resource_group.this, so expect_failures can only
# observe "the resource group raised a precondition failure", not which one. The suite
# therefore does not lean on a single run to attribute a failure to one clause. Instead
# it proves both clauses by ablation against the accepted baseline:
#
#   accepts_apply_and_runtime (deployer + private endpoints)  -> plan succeeds
#   deployer_only_is_rejected (drop private endpoints)        -> rejected
#     => removing the runtime path flips accept->reject, so the runtime clause is real
#   private_endpoints_only_is_rejected (drop deployer)        -> rejected
#     => removing the apply path flips accept->reject, so the apply-time clause is real
#
# module.aks is overridden because a mocked provider returns its computed kubelet_identity
# / kube_config blocks empty, which the module indexes into ([0]); that is a provider-mock
# limitation unrelated to the preconditions under test. The resource group has no
# dependencies, so its precondition is evaluated regardless of the override.

mock_provider "azurerm" {
  # azurerm validates the vault tenant_id as a UUID; it comes from the mocked
  # azurerm_client_config data source, so give it a real-shaped value.
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "random" {}

# Replace the AKS module with its consumed outputs so the plan never evaluates the
# cluster's empty-under-mock computed blocks.
override_module {
  target = module.aks
  outputs = {
    cluster_name    = "aks-autoheal-play"
    oidc_issuer_url = "https://oidc.prod-aks.azure.example/00000000-0000-0000-0000-000000000000/"
    host            = "https://aks-autoheal-play.hcp.centralus.azmk8s.io:443"
  }
}

variables {
  namespace       = "test"
  environment     = "play"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  location        = "centralus"
}

# Accepted baseline: deployer allow-list opens the apply host, private endpoints open the
# runtime path. Both preconditions are satisfied, so the plan must succeed. (This is the
# happy-path case that proves the preconditions accept a valid config rather than always
# rejecting.)
run "accepts_apply_and_runtime" {
  command = plan
  variables {
    deployer_ip_ranges        = ["203.0.113.10"]
    private_endpoints_enabled = true
  }
}

# Allow/Allow opens both paths at once (the playground posture); the plan must succeed.
run "accepts_allow_all" {
  command = plan
  variables {
    storage_network_default_action   = "Allow"
    key_vault_network_default_action = "Allow"
  }
}

# No path at all: both the apply-time and runtime preconditions reject.
run "deny_all_is_rejected" {
  command         = plan
  expect_failures = [azurerm_resource_group.this]
}

# Drop private endpoints from the accepted baseline: the apply host is still reachable,
# but the cluster egress is not, so the runtime precondition rejects. Compared with
# accepts_apply_and_runtime, this isolates the runtime clause.
run "deployer_only_is_rejected" {
  command = plan
  variables {
    deployer_ip_ranges = ["203.0.113.10"]
  }
  expect_failures = [azurerm_resource_group.this]
}

# Drop the deployer allow-list from the accepted baseline: the cluster egress is still
# reachable, but the apply host (a non-VNet runner seeding Key Vault) is not, so the
# apply-time precondition rejects. Compared with accepts_apply_and_runtime, this isolates
# the apply-time clause.
run "private_endpoints_only_is_rejected" {
  command = plan
  variables {
    private_endpoints_enabled = true
  }
  expect_failures = [azurerm_resource_group.this]
}

# A non-canonical casing for the default action is rejected by variable validation,
# before it can reach the Azure API as a confusing deny-all.
run "lowercase_default_action_is_rejected" {
  command = plan
  variables {
    storage_network_default_action = "allow"
  }
  expect_failures = [var.storage_network_default_action]
}
