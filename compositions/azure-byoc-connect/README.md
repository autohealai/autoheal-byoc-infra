# compositions/azure-byoc-connect

The **connect-mode** Azure recipe (Nomura-style): the customer provisions all base
infrastructure and Autoheal only connects the app to it. Consumers run it via
`examples/azure-byoc-connect` (a Terragrunt wrapper); see
[docs/getting-started.md](../../docs/getting-started.md).

Contrast with [`azure-byoc`](../azure-byoc) (create mode), which provisions
everything. This composition provisions almost nothing — it reads existing
resources and binds the app to them, emitting the identical output contract.

## What it reads (existing, by name, in one resource group)

```
AKS cluster             var.aks_cluster_name        (OIDC issuer must be enabled)
PostgreSQL Flexible     var.postgres_server_name
Key Vault               var.key_vault_name
Azure Cache for Redis   var.redis_cache_name
Container Registry      var.acr_name
Storage Account         var.storage_account_name
```

Names are passed explicitly (not derived from the null-label) because the customer's
resources usually follow their own naming.

## What it creates

```
module.workload_identity   app UAMI + federated credentials against the existing
                           cluster's OIDC issuer + role grants:
                             - Storage Blob Data Contributor
                             - AcrPull                  (only if grant_app_acr_pull)
                           (NOT Key Vault — app pods consume ESO-synced Secrets)
module.eso_identity        dedicated ESO UAMI + federated credential against the
                           existing cluster's OIDC issuer (ESO controller SA) +
                           Key Vault Secrets User on the existing vault. The
                           installer reads eso_identity_client_id / eso_tenant_id /
                           eso_service_account to wire the ClusterSecretStore.
azurerm_key_vault_secret   seed secrets (redis-*, postgres-host/user + additional_
                           secrets) when seed_secrets_enabled; the deployer is
                           granted Key Vault Secrets Officer to write them
```

The app identity and ESO identity are split for least privilege (same model as the
create composition and EKS): ESO reads Key Vault with its own identity; the app
identity only reads/writes Blob (and optionally pulls ACR).

`postgres-password` cannot be read back from a server, so pass it (and anything else
the customer created out-of-band) via `additional_secrets`.

## Outputs (shared contract — identical names in `azure-byoc` and `aws-byoc`)

`cluster_name`, `postgres_host`, `redis_endpoint`, `object_store`,
`secret_store_uri`, `registry`, `runner_identity`. Plus `resource_group_name`,
`oidc_issuer_url`, `acr_id`, `kube_host`, and the ESO wiring the installer consumes:
`eso_identity_client_id`, `eso_tenant_id`, `eso_service_account`.
