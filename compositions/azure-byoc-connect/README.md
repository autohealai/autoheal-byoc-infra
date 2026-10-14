# compositions/azure-byoc-connect

The **connect-mode** Azure install: you have already built the base infrastructure
(AKS, PostgreSQL, Key Vault, Redis, ACR, Storage) and Autoheal only connects the app
to it. This composition reads those existing resources and creates the two workload
identities that bind Autoheal's pods to them. It provisions no data services.

If instead you want Autoheal to build everything from scratch, use
[`azure-byoc`](../azure-byoc) (create mode).

New to Terraform/Terragrunt or the state backend? Read
[docs/getting-started.md](../../docs/getting-started.md) first for tool install,
Azure permissions, and remote-state setup. This page is the connect-mode walkthrough.

---

## Before you start

You need all of the following already in place:

1. **The six existing resources, in one resource group and region:** an AKS cluster,
   a PostgreSQL Flexible Server, a Key Vault, an Azure Cache for Redis, a Container
   Registry, and a Storage Account. Have their exact names ready. The Storage
   Account must have blob versioning on and hierarchical namespace off. The Git
   Registry keeps one container per tenant in this account and needs both settings.
   This composition reads the account but does not change its settings. The plan
   stops if hierarchical namespace is on. It cannot read versioning, so check it:

   ```bash
   az storage account show -g <rg> -n <account> --query isHnsEnabled          # false
   az storage account blob-service-properties show -g <rg> --account-name <account> \
     --query isVersioningEnabled                                               # true
   # If versioning is off:
   az storage account blob-service-properties update -g <rg> --account-name <account> \
     --enable-versioning true
   ```

   Also add a rule that deletes old versions (the create composition uses 90 days),
   or old versions stay forever.
2. **AKS OIDC + workload identity enabled** on the cluster (`oidc-issuer` and
   `workload-identity` features). The identities this composition creates federate
   against that issuer; without it the install cannot bind pods to Azure.
3. **The Key Vault in RBAC mode** (`rbac_authorization_enabled = true`). This
   composition grants Key Vault access with Azure RBAC role assignments, which do
   nothing on an access-policy vault. A plan-time check stops you if it is not RBAC.
4. **Permissions to run it:** Owner, or Contributor plus User Access Administrator,
   at the resource-group scope. You are creating user-assigned identities, federated
   credentials, and role assignments, and (if seeding) writing Key Vault secrets.
5. **Tools:** `terraform` (>= 1.6), `terragrunt`, and the Azure CLI (`az`).
6. **A remote-state backend** (an Azure Storage Account + container). See
   [docs/getting-started.md](../../docs/getting-started.md) if you have not set one up.

---

## Step by step

### 1. Sign in to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Collect your existing resource names

Write down the subscription id, region, resource group, and the six resource names.
You will paste them into the config in step 4. A quick way to list them:

```bash
az resource list -g <resource-group> \
  --query "[].{name:name,type:type}" -o table
```

### 3. Copy the example

```bash
cp -r examples/azure-byoc-connect examples/azure-byoc-connect-mine
cd examples/azure-byoc-connect-mine
```

### 4. Fill in `terragrunt.hcl`

Edit every line marked `# EDIT`:

- **`remote_state`** block: your state resource group, storage account, and container.
- **Placement:** `subscription_id`, `location`, `resource_group_name` (the group that
  holds the existing resources).
- **Existing resources:** `aks_cluster_name`, `postgres_server_name`, `key_vault_name`,
  `redis_cache_name`, `acr_name`, `storage_account_name`.
- **Labels for the identity this creates:** `namespace` (your tenant label, e.g. the
  customer name) and `environment` (`stage` | `prod` | `play`).

Leave `federated_service_accounts` commented unless you install the Autoheal chart
into a non-default namespace or with non-default service-account names. The default
matches the three chart service accounts in namespace `autoheal`.

### 5. Add secrets that cannot be read back

The PostgreSQL admin password is never readable from the server, so you must supply
it yourself. Uncomment and set it in `additional_secrets`:

```hcl
seed_secrets_enabled = true
additional_secrets = {
  "postgres-password" = "<the-pg-admin-password>" # pragma: allowlist secret
}
```

If your organization manages its own secrets and does not want this composition to
write any, set `seed_secrets_enabled = false` instead.

### 6. Initialize

```bash
terragrunt init
```

### 7. Review the plan

```bash
terragrunt plan
```

You should see it create only: the app identity and the ESO identity, their federated
credentials, the role grants (Storage Blob Data Contributor on the app identity, Key
Vault Secrets User on the ESO identity), and the optional seed secrets. Everything
else is read-only. If the plan stops on the RBAC precondition, your Key Vault is in
access-policy mode; switch it to RBAC and re-run (see Troubleshooting).

### 8. Apply

```bash
terragrunt apply
```

### 9. Save the outputs

```bash
terragrunt output -json > autoheal-infra-outputs.json
```

### 10. Hand the outputs to the app install

The Autoheal app install reads this file. It is especially important that the app
install consumes the ESO wiring (`eso_identity_client_id`, `eso_tenant_id`,
`eso_service_account`) and deploys the External Secrets Operator under the
`external-secrets/external-secrets` service account. The app identity holds no Key
Vault access on purpose, so if ESO is not wired up, no pod can read secrets.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Plan fails: *"Key Vault ... must use RBAC authorization"* | The vault is in access-policy mode | `az keyvault update -n <vault> --enable-rbac-authorization true`, then re-plan. Review any existing access policies first. |
| Apply fails creating a role assignment (authorization error) | Deployer lacks User Access Administrator / Owner at the scope | Grant the deployer the role, or have someone who holds it run the apply |
| Federated credential error about the OIDC issuer | AKS OIDC / workload identity not enabled | Enable `--enable-oidc-issuer --enable-workload-identity` on the cluster |
| App pods start but secrets are empty | ESO not deployed as `external-secrets/external-secrets`, or the outputs were not consumed | Deploy ESO under that service account and stamp it with `eso_identity_client_id` |

---

## Reference

### What it reads (existing, by name, in one resource group)

```
AKS cluster             var.aks_cluster_name        (OIDC issuer must be enabled)
PostgreSQL Flexible     var.postgres_server_name
Key Vault               var.key_vault_name          (must be RBAC-mode)
Azure Cache for Redis   var.redis_cache_name
Container Registry      var.acr_name
Storage Account         var.storage_account_name
```

Names are passed explicitly (not derived from the null-label) because your resources
usually follow your own naming.

### What it creates

```
module.workload_identity   app UAMI + federated credentials against the existing
                           cluster's OIDC issuer + role grants:
                             - Storage Blob Data Contributor
                             - AcrPull                  (only if grant_app_acr_pull)
                           (NOT Key Vault - app pods consume ESO-synced Secrets)
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

### Outputs

The cross-cloud contract the installer reads, identical names in `azure-byoc` and
`aws-byoc`:

`cluster_name`, `postgres_host`, `object_store`, `secret_store_uri`, `registry`,
`runner_identity`.

`redis_endpoint` (host:ssl_port of the managed Redis) is shared with `aws-byoc` but
**not** `azure-byoc`: the create composition runs Redis in-cluster via the app chart
and emits no managed-Redis endpoint, whereas connect customers always bring a managed
Redis.

Plus `resource_group_name`, `oidc_issuer_url`, `acr_id`, `kube_host`, and the ESO
wiring the installer consumes (shared with `azure-byoc`): `eso_identity_client_id`,
`eso_tenant_id`, `eso_service_account`.
