# The hand-off to the chart: the values this composition outputs as
# autoheal_values (an object, for the app folder) and autoheal_values_yaml (the
# same as YAML, for Helm or Flux). They hold names, endpoints, ARNs and
# addresses, never secrets.
#
#   global.infra   facts: what Terraform built. Only Terraform sets these.
#   global.addons, global.secrets, global.edge, global.llm
#                  suggestions that follow from what was built. The customer's
#                  values file may override them.
#   global.imageRegistry
#                  suggestion, only when there is a registry (create_registry or
#                  existing_registry_url). The chart then pulls
#                  <registry>/app/<name> and <registry>/external/<name>.
#   temporal, zitadel
#                  copies of the database host and the login hostname at the
#                  paths those upstream charts read, and with a registry the
#                  Temporal and Zitadel image repositories under
#                  <registry>/external. The chart checks that each copy matches
#                  its fact or global.imageRegistry.
#
# AWS has no identities block: the Pod Identity associations bind the chart's
# service accounts to their roles, so the chart needs no annotation. The chart
# binds its load balancer Services to global.infra.targetGroups.
#
# Bump infra_contract_version when the shape of global.infra changes; the chart
# refuses a version older than it needs for the cloud.

locals {
  infra_contract_version = "2.1.0"

  autoheal_values = {
    global = merge({
      infra = merge(
        {
          version = local.infra_contract_version
          cloud   = "aws"
          region  = var.region
          hosts   = local.hosts
          # Install entry <e> is the Secrets Manager secret <prefix><e>.
          secretsManager = {
            prefix = local.secrets_prefix
          }
          # Where api-server-go keeps the integration credentials users enter:
          # <prefix>/tenants/<tenant>/... in this account and region.
          runtimeSecrets = {
            kind   = "awssecretsmanager"
            region = var.region
            prefix = local.runtime_secrets_prefix
          }
          database = {
            host                    = local.postgres_host
            port                    = 5432
            adminUser               = local.postgres_admin_login
            adminPasswordVaultEntry = "postgres-admin-password"
          }
          objectStore = {
            kind               = "s3"
            bucket             = local.attachments_bucket
            artifactsBucket    = local.artifacts_bucket
            tenantBucketPrefix = local.tenant_bucket_prefix
          }
          # NLB target groups (target type ip) the chart binds its Services to.
          # edgeHttps and edgeHttp only in loadbalancer mode.
          targetGroups = local.target_group_arns
        },
        # Redis only when there is one.
        { for k, v in { redis = { host = local.redis_host, port = local.redis_port } } : k => v if local.redis_enabled },
      )

      addons = {
        # The Secrets Store CSI driver and its AWS provider come from the EKS
        # add-on (aws-secrets-store-csi-driver-provider), so the chart installs
        # nothing.
        install = false
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
      # Only the gateway entries, when llm_gateway_extra_headers is set: the
      # headers entry, and an empty key entry when llm_gateway_api_key is unset,
      # since Secrets Manager then has no gateway-api-key. A kind that needs a key
      # then stops at the chart's check instead of a failed secret mount. The rest
      # of global.llm, the gateway switch included, is the customer's.
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
