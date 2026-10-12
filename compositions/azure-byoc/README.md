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

## Network & access posture

Blob and Key Vault default to **deny-all** firewalls, and private endpoints are **off**
by default. These firewalls gate **two distinct data-plane paths that do not share a
source IP**, so both must be opened:

1. **Apply-time** — Terraform seeds Key Vault secrets and creates the blob container
   from the apply host. Open it with `deployer_ip_ranges = ["<apply-host-egress>/32"]`
   (the apply host's *public* egress). A private endpoint does **not** cover this unless
   Terraform runs inside the VNet, so seeding always uses the public+allow-list path and
   never races the private-endpoint module.
2. **Runtime** — AKS pods (ESO reading secrets, the app reading blobs) egress via the
   **cluster's outbound IP**, not the apply host, so `deployer_ip_ranges` does nothing
   for them. Open it with `private_endpoints_enabled = true` (recommended), or
   `workload_egress_ip_ranges = ["<cluster-outbound>/32"]` when private endpoints are off.

For a throwaway/playground install, set `storage_network_default_action` and
`key_vault_network_default_action = "Allow"` to satisfy both at once.

The composition enforces each path with a separate plan-time precondition, so a missing
apply-time or runtime path surfaces at plan rather than as an opaque 403 mid-apply or a
silently broken ESO at runtime.

AKS access controls (all optional, default to the open-but-public posture):

- `admin_group_object_ids` — turns on managed-Entra RBAC **and** disables the
  static-certificate local admin accounts (`--admin` kubeconfigs).
- `api_server_authorized_ip_ranges` — restricts the public API server to known CIDRs.
- `private_cluster_enabled` — removes the public API endpoint entirely (requires
  in-VNet / peered connectivity for `kubectl` and Terraform).

## Outputs (shared contract — identical names in `aws-byoc`)

`cluster_name`, `postgres_host`, `object_store`, `secret_store_uri`, `registry`,
`runner_identity`. Plus `resource_group_name`, `oidc_issuer_url`, `acr_id`,
`runner_subnet_id`, `kube_host`. (`redis_endpoint` is intentionally omitted on
Azure — Redis is in-cluster; see above.)
