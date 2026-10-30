# Temporal on a VM of its own, optional: for a cluster that cannot run the
# Temporal server. The app and the runner reach it on <public IP>:7233, with
# TLS and a key. See the README of compositions/azure-temporal.
#
# Order:
#   1. Apply ../infra: it makes Postgres, the temporal databases and the
#      runner key (vault entry runner-token).
#   2. Apply this unit with start_temporal = false. The VM runs only the
#      proxy; nothing touches the database.
#   3. Apply ../app with temporal.server.replicaCount: 0, nothing else changed.
#      The in-cluster Temporal servers stop.
#   4. Once no Temporal server pod is left in the cluster, set
#      start_temporal = true and apply again. This replaces the VM (the public
#      IP stays); the new one upgrades the schema and starts Temporal.
#   5. Apply ../app with the chart pointed at temporal_address and the
#      in-cluster Temporal off. It reads the app key and the CA from the vault
#      entries this unit writes. If this apply fails, Helm rolls back to step
#      3, with no Temporal server in the cluster.
#   6. Point ../runner at temporal_address, temporal_server_name and
#      temporal_ca_certificate, and apply it.
#
# The Temporal database password is a secret, so it is not in this file. Read
# it from the vault entry temporal-db-password that ../infra wrote and pass it
# as TF_VAR_temporal_db_password:
#   export TF_VAR_temporal_db_password="$(az keyvault secret show \
#     --vault-name <vault> --name temporal-db-password --query value -o tsv)"
# The vault name is global.infra.keyVault.name in ../infra's autoheal_values.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

# compositions/azure-temporal is new after 4.1.2: infra_version in
# versions.hcl must be a release that has it.
terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure-temporal?ref=v${local.v.infra_version}"
}

# The runner key. This unit reads nothing else from ../infra.
dependency "infra" {
  config_path = "../infra"

  # Before ../infra is applied there are no outputs yet. The plan uses this
  # placeholder for what is missing (shallow); the apply always uses the real
  # key.
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs = {
    runner_token = "pendingpendingpendingpendingpending"
  }
}

inputs = {
  namespace   = "acme"
  environment = "prod"
  location    = "eastus2" # the cluster's region

  # The data subscription, as in ../infra. Postgres must be in it.
  subscription_id = "11111111-2222-3333-4444-555555555555"

  # Who may reach 7233: the cluster's public outbound addresses (as
  # workload_egress_ip_ranges in ../infra) and the runner's NAT IP (the
  # egress_ip output of ../runner). Add the runner's address once ../runner is
  # applied; a change here touches only the NSG, not the VM.
  allowed_source_cidrs = ["198.51.100.20/32"]

  runner_token = dependency.infra.outputs.runner_token

  # The Postgres server ../infra made. Its public access must be on: this unit
  # adds a firewall rule for the VM's IP.
  postgres_server_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
  postgres_fqdn      = "acme-prod-autoheal-db.postgres.database.azure.com"

  # The install vault of ../infra. The app key and the CA go there as
  # temporal-app-key and temporal-ca, where the chart reads them. The apply
  # needs Key Vault Secrets Officer on it and a deployer IP the vault lets in,
  # as for ../infra.
  key_vault_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/acme-prod-autoheal"

  # False until no Temporal pod is left in the cluster. Two Temporal servers on
  # one database break it. See the order above.
  start_temporal = false
}
