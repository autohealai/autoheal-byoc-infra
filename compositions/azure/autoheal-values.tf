# The hand-off to the chart: the values this composition outputs as
# autoheal_values (an object, for the app folder) and autoheal_values_yaml (the
# same as YAML, for Helm or Flux). They hold names, endpoints, identity client IDs
# and addresses, never secrets.
#
#   global.infra   facts: what Terraform built. Only Terraform sets these.
#   global.addons, global.secrets, global.edge
#                  suggestions that follow from what was built. The customer's
#                  values file may override them.
#   temporal, zitadel
#                  copies of the database host and the login hostname at the
#                  paths those upstream charts read. The chart checks that each
#                  copy equals its fact.
#
# Bump infra_contract_version when the shape of global.infra changes; the chart
# refuses a version older than its autoheal.io/min-infra-version.

locals {
  infra_contract_version = "2.0.0"

  autoheal_values = {
    global = {
      infra = merge(
        {
          version = local.infra_contract_version
          cloud   = "azure"
          hosts   = local.hosts
          keyVault = {
            name     = local.key_vault_name
            tenantId = local.key_vault_tenant_id
          }
          identities = {
            secrets      = module.secrets_identity.client_id
            apiServer    = module.api_server_identity.client_id
            agentsWorker = module.agents_worker_identity.client_id
          }
          database = {
            host                    = local.postgres_host
            port                    = 5432
            adminUser               = local.postgres_admin_login
            adminPasswordVaultEntry = "postgres-admin-password"
          }
          objectStore = {
            kind      = "azure-blob"
            account   = local.storage_account_name
            container = var.storage_container_name
          }
          temporal = {
            internalIP = local.temporal_ip
          }
        },
        # Optional keys: Redis only when there is one, the proxy address only in
        # loadbalancer mode.
        { for k, v in { redis = { host = local.redis_host, port = local.redis_port } } : k => v if local.redis_enabled },
        { for k, v in { edge = { internalIP = local.proxy_ip } } : k => v if var.edge_mode == "loadbalancer" },
      )

      addons = {
        # true only when this composition created the cluster. No effect on
        # Azure, where the CSI driver is an AKS add-on.
        install = local.create_cluster
      }
      secrets = {
        mode = "keyvault-csi"
      }
      # The CA entry is suggested only when edge_ca_certificate is set.
      edge = merge(
        { mode = var.edge_mode },
        { for k, v in { tls = { caVaultEntry = "edge-ca-certificate" } } : k => v if var.edge_ca_certificate != "" },
      )
    }

    temporal = {
      server = {
        config = {
          persistence = {
            default = {
              sql = { host = local.postgres_host }
            }
            visibility = {
              sql = { host = local.postgres_host }
            }
          }
        }
      }
    }

    zitadel = {
      zitadel = {
        configmapConfig = {
          ExternalDomain = local.hosts.auth
          Database = {
            Postgres = {
              Host = local.postgres_host
            }
          }
        }
      }
    }
  }
}
