# Temporal on a VM of its own, optional: for a cluster that cannot run the
# Temporal server. The app and the runner reach it on <temporal_ip>:7233, or
# on dns_name, with TLS and a key. A gate on the VM checks the key on every
# call. See the README of compositions/azure-temporal.
#
# Order:
#   1. Apply ../infra: it makes Postgres, the temporal databases and the
#      runner key (vault entry runner-token).
#   2. Apply this unit with start_temporal = false. The VM runs only the gate;
#      nothing touches the database.
#   2b. Add "<temporal_ip>/32" to workload_egress_ip_ranges in ../infra and
#      apply it, so the VM can read its keys from the vault. Until then the
#      gate does not start.
#   3. Apply ../app with temporal.server.replicaCount: 0, nothing else changed.
#      The in-cluster Temporal servers stop.
#   4. Once no Temporal server pod is left in the cluster, start Temporal on
#      the VM with az vmss run-command (see the README), then set
#      start_temporal = true and apply again. That apply does not touch the VM.
#   5. Apply ../app with the chart pointed at temporal_address and the
#      in-cluster Temporal off. It reads the keys from the vault entries
#      temporal-api-server-key and temporal-agents-key, and the CA from
#      temporal-ca. If this apply fails, Helm rolls back to step 3, with no
#      Temporal server in the cluster.
#   6. Point ../runner at this unit's outputs (see the note there) and apply
#      it. Then add its egress_ip to allowed_source_cidrs here and apply again.
#
# The Temporal database password is a secret, so it is not in this file. Read
# it from the vault entry temporal-db-password that ../infra wrote and pass it
# as TF_VAR_temporal_db_password:
#   export TF_VAR_temporal_db_password="$(az keyvault secret show \
#     --vault-name <vault> --name temporal-db-password --query value -o tsv)"
# The vault name is global.infra.keyVault.name in ../infra's autoheal_values.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

# compositions/azure-temporal is new after 4.2.0: infra_version in
# versions.hcl must be a release that has it.
terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure-temporal?ref=v${local.v.infra_version}"
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

  # The Postgres server ../infra made. Its public access must be on: this unit
  # adds a firewall rule for the VM's IP.
  postgres_server_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-prod-autoheal-db"
  postgres_fqdn      = "acme-prod-autoheal-db.postgres.database.azure.com"

  # The install vault of ../infra, the one with runner-token. The two app keys
  # go there, and with the private CA also temporal-tls and temporal-ca. The
  # apply needs Key Vault Secrets Officer on it and a deployer IP the vault lets
  # in, as for ../infra. The VM reads the vault too: see step 2b.
  key_vault_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-autoheal/providers/Microsoft.KeyVault/vaults/acme-prod-autoheal"

  # By default clients dial the IP and trust a private CA made here, with
  # temporal.autoheal.internal as the server name. To use a DNS name and a
  # certificate from a CA the clients already trust, make a Key Vault
  # certificate for that name in the vault above, point the name at the
  # temporal_ip output, and set both:
  # dns_name         = "temporal.autoheal.acme.example"
  # certificate_name = "temporal-autoheal-acme-example"

  # Optional: send the VM's logs to a workspace, and the health alert to action
  # groups.
  # log_analytics_workspace_id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-monitor/providers/Microsoft.OperationalInsights/workspaces/log-acme-prod"
  # action_group_ids           = ["/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-acme-prod-monitor/providers/Microsoft.Insights/actionGroups/ag-acme-prod-oncall"]

  # False until Temporal runs on the VM. Two Temporal servers on one database
  # break it. See step 4 above.
  start_temporal = false
}
