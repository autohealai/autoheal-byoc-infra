# The hand-off to the chart: the values this composition outputs as
# autoheal_values (an object, for the app folder) and autoheal_values_yaml (the
# same as YAML, for Helm or Flux). They hold names, endpoints, identity client IDs
# and addresses, never secrets.
#
#   global.infra   facts: what Terraform built. Only Terraform sets these.
#   global.addons, global.secrets, global.edge, global.llm
#                  suggestions that follow from what was built. The customer's
#                  values file may override them.
#   global.imageRegistry
#                  suggestion, only when there is a registry (create_registry or
#                  existing_acr_id): its login server. The chart then pulls
#                  <registry>/app/<name> and <registry>/external/<name>.
#   temporal, zitadel
#                  copies of the database host and the login hostname at the
#                  paths those upstream charts read, and with a registry the
#                  Temporal and Zitadel image repositories under
#                  <registry>/external. The chart checks that each copy matches
#                  its fact or global.imageRegistry.
#
# Bump infra_contract_version when the shape of global.infra changes; the chart
# refuses a version older than its autoheal.io/min-infra-version.

locals {
  infra_contract_version = "2.0.0"

  # Registry login server, or "" without a registry. Every key built from it is
  # left out when it is "", so the chart's default public registry applies.
  image_registry = local.acr_login_server

  autoheal_values = {
    global = merge({
      infra = merge(
        {
          version = local.infra_contract_version
          cloud   = "azure"
          hosts   = local.hosts
          keyVault = {
            name     = local.key_vault_name
            tenantId = local.key_vault_tenant_id
          }
          # Where api-server-go keeps the integration credentials users enter.
          # A separate vault from keyVault; see keyvault.tf.
          runtimeSecrets = {
            kind     = "azurekeyvault"
            vaultURL = local.runtime_key_vault_url
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
      },
      { for k, v in { imageRegistry = local.image_registry } : k => v if local.image_registry != "" },
      # Only the gateway vault entries, when llm_gateway_extra_headers is set:
      # the headers entry, and an empty key entry when llm_gateway_api_key is
      # unset, since the vault then has no gateway-api-key. A kind that needs a
      # key then stops at the chart's check instead of a failed vault mount.
      # The rest of global.llm, the gateway switch included, is the customer's.
      { for k, v in { llm = { gateway = merge(
        { extraHeadersVaultEntry = "gateway-extra-headers" },
        { for k, v in { apiKeyVaultEntry = "" } : k => v if nonsensitive(var.llm_gateway_api_key == "") },
      ) } } : k => v if nonsensitive(var.llm_gateway_extra_headers != "") },
    )

    temporal = merge(
      {
        server = merge(
          {
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
          },
          { for k, v in { image = { repository = "${local.image_registry}/external/temporal-server" } } : k => v if local.image_registry != "" },
        )
      },
      { for k, v in {
        web        = { image = { repository = "${local.image_registry}/external/temporal-ui" } }
        admintools = { image = { repository = "${local.image_registry}/external/temporal-admin-tools" } }
      } : k => v if local.image_registry != "" },
    )

    zitadel = merge(
      {
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
      },
      { for k, v in { image = { repository = "${local.image_registry}/external/zitadel" } } : k => v if local.image_registry != "" },
      { for k, v in { login = { image = { repository = "${local.image_registry}/external/zitadel-login" } } } : k => v if local.image_registry != "" },
      { for k, v in { imageRegistry = local.image_registry } : k => v if local.image_registry != "" },
    )
  }
}
