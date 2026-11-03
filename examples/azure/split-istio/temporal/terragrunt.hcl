# Temporal on a VM of its own, optional: for a cluster that cannot run the
# Temporal server. The app and the runner reach it on <temporal_ip or
# dns_name>:<client_port>, 7233 by default, with TLS and a key. A gate on the
# VM checks the key on every call. See the README of
# compositions/azure-temporal.
#
# Order:
#   1. Apply ../infra: it makes Postgres, the temporal databases, the runner
#      key (vault entry runner-token) and the database password (vault entry
#      temporal-db-password).
#   2. Apply this unit with start_temporal = false. The VM runs only the gate;
#      nothing touches the database.
#   2b. Add "<temporal_ip>/32" to workload_egress_ip_ranges in ../infra and
#      apply it, so the VM can read its keys from the vault. Until then the
#      gate does not start. This unit reads that list too and leaves the VM's
#      own IP out, so it plans no change.
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
# This unit takes the rest from ../infra: the naming, the subscription, the
# region and the cluster's addresses from its inputs, and the vault, the
# Postgres server and the database password through its autoheal_values
# output. The password is read from the vault, so it is not in this file or
# the environment.

locals {
  v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals

  # The inputs of ../infra, so nothing is typed twice.
  infra = read_terragrunt_config("${get_terragrunt_dir()}/../infra/terragrunt.hcl").inputs

  # The cluster's outbound addresses from ../infra, each as a CIDR: the vaults
  # take a plain address, the NSG needs 198.51.100.20/32.
  cluster_cidrs = [for c in try(local.infra.workload_egress_ip_ranges, []) : can(cidrhost(c, 0)) ? c : "${c}/32"]
}

include "root" { path = find_in_parent_folders("root.hcl") }

# compositions/azure-temporal is new in 4.3.0, infra_values in 4.3.1 and
# client_port in 4.6.0: infra_version in versions.hcl must be 4.3.1 or later,
# or 4.6.0 or later with client_port.
terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/azure-temporal?ref=v${local.v.infra_version}"
}

# The names of the vault and the Postgres server. Runs after ../infra.
dependency "infra" {
  config_path = "../infra"

  # The plan needs the real names, so the placeholder is for init and
  # validate only.
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
  mock_outputs = {
    autoheal_values = {}
  }
}

inputs = {
  namespace   = local.infra.namespace
  environment = local.infra.environment
  location    = local.infra.location

  # The data subscription of ../infra. Postgres and the vault are found in it
  # by name.
  subscription_id = local.infra.subscription_id

  # The install vault, the one with runner-token, and the Postgres server. The
  # two app keys go to the vault, and with the private CA also temporal-tls and
  # temporal-ca. The apply needs Key Vault Secrets Officer on it and a deployer
  # IP the vault lets in, as for ../infra. The VM reads the vault too: see step
  # 2b. Postgres public access must be on: this unit adds a firewall rule for
  # the VM's IP.
  infra_values = dependency.infra.outputs.autoheal_values

  # Who may reach Temporal: the cluster's public outbound addresses, from ../infra,
  # and the runner's NAT IP (the egress_ip output of ../runner) once ../runner
  # is applied. A change here touches only the NSG, not the VM.
  allowed_source_cidrs = concat(local.cluster_cidrs, [
    # "198.51.100.30/32", # egress_ip of ../runner, after step 6
  ])

  # The port clients dial, 7233 by default. 443 suits a network that lets only
  # HTTPS out, if its firewall passes TLS through without decrypting it. A
  # firewall that allows by name checks the server name, so set dns_name too.
  # Changing it on a running install updates the load balancer rule in place:
  # clients on the old port lose Temporal until the app and ../runner move to
  # the new temporal_address. See "Port" in the README of compositions/azure-temporal.
  # client_port = 443

  # By default clients dial the IP and trust a private CA made here, with
  # temporal.autoheal.internal as the server name. To use a DNS name and a
  # certificate from a CA the clients already trust, make a Key Vault
  # certificate for that name in the install vault, point the name at the
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
