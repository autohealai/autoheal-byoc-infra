# Copyable starting config for an Azure / AKS BYOC install.
#
#   cp -r examples/azure-byoc examples/azure-byoc-mine
#   cd examples/azure-byoc-mine
#   # edit the inputs + remote_state below
#   terragrunt init && terragrunt plan && terragrunt apply
#   terragrunt output -json > autoheal-infra-outputs.json
#
# See docs/getting-started.md.

terraform {
  # Pin a release when consuming across repos; here we point at the composition in
  # this checkout.
  source = "${get_repo_root()}//compositions/azure-byoc"
}

# Remote state: one storage account/container holds this install's state. Create it
# ONCE with scripts/bootstrap-state-azure.sh (Terraform cannot create the account
# that stores its own state), then put the matching names here. Terragrunt feeds
# these to the composition's partial `backend "azurerm"` block at init.
remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-autoheal-tfstate" # EDIT: state RG (bootstrap arg)
    storage_account_name = "stautohealtfstate"   # EDIT: state storage account, 3-24 lowercase alnum, globally unique (bootstrap arg)
    container_name       = "tfstate"
    key                  = "azure-byoc/terraform.tfstate"
  }
}

inputs = {
  # Identity / naming (environment = lifecycle, not region)
  namespace   = "REPLACE_ME" # EDIT: customer / tenant short name, e.g. "acme"
  environment = "play"       # EDIT: stage | prod | play
  name        = "autoheal"

  # Placement
  subscription_id = "REPLACE_ME" # EDIT: az account show --query id -o tsv
  location        = "centralus"  # EDIT: PG Flexible region (centralus | westus3 | northcentralus)

  # Network reachability for Blob + Key Vault. Both default to deny-all firewalls, and
  # the composition refuses to plan without a reachable path. This is a PLAYGROUND config,
  # so it opens them with default_action = Allow to keep the copy-paste flow working.
  #
  # For stage/prod, DELETE the two Allow lines below and instead set:
  #   private_endpoints_enabled = true                      # runtime path for AKS pods
  #   deployer_ip_ranges        = ["<apply-host-egress>/32"] # apply-time path to seed Key Vault
  # (or, without private endpoints, add workload_egress_ip_ranges = ["<cluster-outbound>/32"]).
  storage_network_default_action   = "Allow"
  key_vault_network_default_action = "Allow"

  # Optional knobs (defaults are sensible; uncomment to change)
  # address_space             = ["10.60.0.0/16"]
  # private_endpoints_enabled = false
  # postgres_sku_name         = "GP_Standard_D2ds_v5"
  # node_vm_size              = "Standard_D4s_v6"
  # node_min_count            = 2
  # node_max_count            = 4
  # acr_sku                   = "Standard"

  # ---------------------------------------------------------------------------
  # Backup, high availability and encryption at rest.
  #
  # The defaults preserve a minimal playground posture (7-day local backup, no HA,
  # Microsoft-managed key). For a REAL (stage/prod) install, uncomment the block
  # below. A few of these cannot be changed after the first apply, so decide them up
  # front:
  #   - postgres_geo_redundant_backup_enabled : CREATE-TIME ONLY
  #   - key_vault_soft_delete_retention_days  : CREATE-TIME ONLY
  #   - key_vault_purge_protection_enabled    : IRREVERSIBLE once on
  #   - cmk_enabled                           : CREATE-TIME ONLY on Postgres
  # ---------------------------------------------------------------------------
  # postgres_backup_retention_days        = 35     # keep 35 days of restorable backups
  # postgres_geo_redundant_backup_enabled = true   # copy backups to the paired region
  # postgres_auto_grow_enabled            = true   # grow storage before it fills (on by default)
  # postgres_high_availability_enabled    = true   # hot standby in a second zone, auto failover
  # postgres_delete_protection_enabled    = true   # block accidental server deletion
  #
  # blob_replication_type                     = "GRS" # ZRS (in-region zones) or GRS (paired region)
  # blob_soft_delete_retention_days           = 30
  # blob_container_soft_delete_retention_days = 30
  # blob_pitr_enabled                         = true  # point-in-time restore
  # blob_restore_days                         = 29    # must be < blob_soft_delete_retention_days
  #
  # key_vault_soft_delete_retention_days = 90
  # key_vault_purge_protection_enabled   = true
  #
  # cmk_enabled = true   # customer-managed key for Postgres + Blob (requires purge protection on)

  # App-identity federation. The default already matches the autoheal-byoc chart
  # (api-server-go, agents-py-http, agents-py-worker in namespace "autoheal").
  # Only override if you install the app into a different namespace or SA names.
  # federated_service_accounts = [
  #   { namespace = "autoheal", service_account = "api-server-go" },
  #   { namespace = "autoheal", service_account = "agents-py-http" },
  #   { namespace = "autoheal", service_account = "agents-py-worker" },
  # ]
}
