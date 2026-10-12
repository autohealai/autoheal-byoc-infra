# compositions/azure-byoc

The Azure recipe: wires the `modules/azure/*` building blocks into the Autoheal
BYOC stack and emits the shared output contract. Consumers run it via
`examples/azure-byoc` (a Terragrunt wrapper); see
[docs/CONSUMING.md](../../docs/CONSUMING.md).

## What it creates

```
azurerm_resource_group         rg-<namespace>-<environment>-<name>
random_password.postgres       -> seeded into Key Vault, never a root output
module.vnet                    VNet + subnets + NAT + PG/privatelink DNS zones
module.postgres                PG Flexible (subnet = vnet.subnet_db_id)
module.blob                    Storage Account + container
module.acr                     Container Registry
module.keyvault                Key Vault + seeded PG secrets
module.aks                     AKS (subnet = vnet.subnet_aks_id, acr = acr.acr_id)
module.workload_identity       UAMI federated to the app SAs (+ KV/Blob grants)
module.pe_blob / module.pe_vault   private endpoints (when private_endpoints_enabled)
```

## Deliberately not here

- **Runner VMSS** (`modules/azure/runner-vmss`) — it needs `temporal_host` (the
  internal LB IP), which only exists after the app + Temporal are deployed. Run it
  as a separate apply afterwards, fed by this composition's `runner_subnet_id`,
  `acr_id`, and `acr_name`. This mirrors the AWS runner unit.

- **Redis** — runs **in-cluster** (a StatefulSet shipped by the app Helm chart) at
  a fixed service DNS name, so it is not provisioned or output here (no managed
  cache, no `snet-redis`, no `redis-*` Key Vault secrets). Customers who bring
  their own managed Redis use `azure-byoc-connect`, which still reads it.

## Outputs (shared contract — identical names in `aws-byoc`)

`cluster_name`, `postgres_host`, `object_store`, `secret_store_uri`, `registry`,
`runner_identity`. Plus `resource_group_name`, `oidc_issuer_url`, `acr_id`,
`runner_subnet_id`, `kube_host`. (`redis_endpoint` is intentionally omitted on
Azure — Redis is in-cluster; see above.)
