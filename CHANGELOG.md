# Changelog

All notable changes to this repo are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/). One version covers the whole repo.

## [Unreleased]

## [1.4.0] - 2026-10-16

### Added
- `azure/postgres-flexible`: backup, high-availability and encryption controls, each
  defaulting to the current behaviour. `backup_retention_days` (1-35, default 7),
  `geo_redundant_backup_enabled` (copy backups to the paired region; **create-time
  only**), `auto_grow_enabled` (default `false`; recommended on for a real install),
  `high_availability_enabled`
  (zone-redundant hot standby), `delete_protection_enabled` (a `CanNotDelete`
  management lock, the Azure twin of `aws/rds-cluster` deletion protection), and
  `cmk_key_vault_key_id` / `cmk_identity_id` for a customer-managed key (**create-time
  only**; the vault must have purge protection on).
- `azure/blob`: point-in-time restore (`pitr_enabled`, `blob_restore_days`; turns on
  the change feed with a bounded retention, guarded so the restore window stays shorter
  than the soft-delete window and versioning/soft-delete are on) and
  `cmk_key_vault_key_id` / `cmk_identity_id` for a customer-managed key.
- `azure/keyvault`: `soft_delete_retention_days` is now configurable (7-90, default 7;
  **create-time only**). It was previously hardcoded to 7.
- `azure-byoc`: pass-through variables for all of the above, plus a `cmk_enabled`
  switch that creates a customer-managed key in the stack's own Key Vault with a
  dedicated encryption identity and the required crypto role assignments, and wires it
  into Postgres and Blob. Gated on `key_vault_purge_protection_enabled = true`.
- `examples/azure-byoc`: a documented, ready-to-uncomment production block for the
  backup/HA/encryption values, with the create-time/irreversible settings flagged.
- `docs/getting-started.md`: a production-hardening note under Step 4 pointing at the
  backup/HA/encryption settings and the decisions that must be made before the first
  apply.
- `azure/postgres-flexible`: a plan-time precondition rejects enabling a
  customer-managed key and geo-redundant backup together. That combination requires a
  paired-region geo-backup key which is not yet supported, so the guard fails during
  `plan` with a readable message instead of a cryptic Azure 400 part way through apply.
  Enable one or the other.
- `azure/blob`, `azure/postgres-flexible`: plan-time preconditions require the CMK key
  id and encryption identity id to be set together (both or neither), and the blob
  module additionally requires versioning and soft delete to be on when PITR is
  enabled.
- `azure/blob`: the change feed now has a bounded retention
  (`change_feed_retention_in_days`, tied to the restore window) so the log cannot grow
  without limit, and last-access tracking is no longer coupled to PITR (it is not a PITR
  requirement).
- `azure-byoc`: the storage account's customer-managed key uses the versionless key id
  so it auto-rotates to new key versions; Postgres keeps the versioned id, which the
  provider requires.

## [1.3.0] - 2026-10-14

### Added
- `azure/blob`: blob versioning on the storage account (`versioning_enabled`, default
  `true`). It is the Azure equivalent of the S3 bucket versioning the app sets on AWS.
  The Git Registry expects it. The app identity has data-plane access only, so the
  module owns this account setting.
- `azure/blob`: a management policy `expire-noncurrent-versions` deletes old blob
  versions after `noncurrent_version_expiration_days` (default 90, the same as
  `aws/s3`). The rule has no prefix, so it covers every tenant container.
- `azure/blob`: blob and container soft delete, set explicitly
  (`blob_soft_delete_retention_days`, `container_soft_delete_retention_days`, default 7;
  0 = off). The `blob_properties` block makes Terraform own all blob-service
  properties, so an omitted retention policy would be turned off.
- `azure-byoc` and `azure-byoc-connect` output `blob_endpoint` (the primary blob
  endpoint of the storage account). The installer passes it to api-server-go as
  `GIT_REGISTRY_AZURE_STORAGE_ACCOUNT_URL`. It is Azure-only, so it is in the extras
  section, not in the shared contract.
- `azure-byoc-connect`: a plan-time check stops the plan if the existing Storage
  Account has hierarchical namespace on. `connect.tftest.hcl` proves it.

### Changed
- `azure/blob`: set `is_hns_enabled = false` explicitly. The Git Registry needs a flat
  namespace. This is the provider default, so existing accounts do not change.
- `azure-byoc-connect` README: the existing Storage Account must have blob versioning
  on and hierarchical namespace off. The README gives the `az` commands to check and
  set versioning, because the data source cannot read it.

## [1.2.0] - 2026-10-13

### Added
- `azure-byoc-connect`: a dedicated, least-scoped **ESO identity** (`module.eso_identity`,
  `modules/azure/external-secrets`) — a user-assigned identity federated to the existing
  cluster's OIDC issuer and the External Secrets controller ServiceAccount, granted
  **Key Vault Secrets User** on the existing vault. Brings connect to parity with the create
  composition so the installer's Azure Key Vault + ESO path can stand up app secrets.
- `azure-byoc-connect` outputs `eso_identity_client_id`, `eso_tenant_id`,
  `eso_service_account` (the ESO wiring the installer reads to stamp the controller
  ServiceAccount and configure the `ClusterSecretStore`).
- `azure-byoc-connect`: a plan-time precondition that the existing Key Vault uses RBAC
  authorization (`rbac_authorization_enabled = true`). The composition grants Key Vault
  access via Azure RBAC role assignments, which silently grant nothing on an access-policy
  vault; the guard fails the plan instead of shipping a green apply with a dead runtime.
- `azure-byoc-connect/tests/connect.tftest.hcl`: a mocked-provider `terraform test` that
  plans the composition and asserts the shared output contract + optional seeding, applies
  to prove the app and ESO identities are distinct principals, and asserts the RBAC guard
  rejects an access-policy vault.
- CI runs `terraform test` on every composition that ships a `tests/` directory (was
  `azure-byoc` only), and fails the step if discovery finds none.

### Changed
- `azure-byoc-connect`: `federated_service_accounts` now defaults to the three real chart
  ServiceAccounts in namespace `autoheal` (`api-server-go`, `agents-py-http`,
  `agents-py-worker`), matching the create composition; the previous `app/autoheal-app`
  default matched no pod.
- Rewrote `compositions/azure-byoc-connect/README.md` as a step-by-step tutorial:
  a "Before you start" prerequisites checklist, ten numbered steps (sign in → collect
  existing resource names → copy the example → fill `terragrunt.hcl` → seed the PG
  password → init → plan → apply → save outputs → hand off to the app install), a
  troubleshooting table, and a reference section.
- Point the README source example and the `docs/getting-started.md` checkout steps at
  `v1.2.0`.

### Removed
- `azure-byoc-connect`: the **app** identity no longer receives Key Vault Secrets User
  (`kv_role_enabled = false`). ESO reads the vault with its own identity; app pods consume
  the Kubernetes Secrets ESO syncs (least privilege; mirrors create and EKS).

> **Upgrade note (connect installs):** re-applying `azure-byoc-connect` creates the new ESO
> user-assigned identity, its federated credential, and a Key Vault Secrets User role
> assignment, and **removes** the app identity's Key Vault Secrets User role assignment. The
> app install must now consume the `eso_identity_*` outputs (ESO reads Key Vault via its own
> identity). No data-plane resources are modified.

## [1.1.2] - 2026-10-12

> Docs-only release. No infrastructure (module/composition) changes from
> `v1.1.0`/`v1.1.1` — the deployed stack is identical.

### Changed
- Renamed the consumer guide `docs/CONSUMING.md` → `docs/getting-started.md`
  (clearer, industry-standard "start here" name) and updated all references in
  the README, compositions, and examples.
- Point the README source example and the `docs/getting-started.md` checkout
  steps at `v1.1.2`.

## [1.1.1] - 2026-10-12

> Docs- and governance-only release. No infrastructure (module/composition)
> changes from `v1.1.0` — the deployed stack is identical. This tag exists so a
> customer who pins a release also gets the `LICENSE`, which was added after the
> `v1.1.0` tag.

### Added
- Repository governance files: `LICENSE` (MIT, matching `autohealai/agents`),
  `.github/CODEOWNERS`, `SECURITY.md` (private vulnerability reporting), and
  `CONTRIBUTING.md` (the module-standard contract, local checks, and the
  release/versioning flow).

### Changed
- Point the README source example and the `docs/CONSUMING.md` checkout steps at
  `v1.1.1` (was `v1.0.0`, which predates the workload-identity federation fix;
  `v1.1.0` carried the fix but predates the `LICENSE`).

## [1.1.0] - 2026-10-12

> **Upgrade notes.** The Blob and Key Vault firewalls now **default to `Deny`**, and
> the composition refuses to `plan` without a reachable data-plane path. A config
> that planned cleanly on `v1.0.0` may now stop at a precondition until you set one
> of: `private_endpoints_enabled = true`, `deployer_ip_ranges` /
> `workload_egress_ip_ranges`, or `*_network_default_action = "Allow"` (playgrounds
> only). The shipped `examples/azure-byoc` uses `Allow` so the first run just works.

### Added
- `acr_name` output on `compositions/azure-byoc` — the separate runner-VMSS apply
  needs it alongside `acr_id`.
- Azure AKS access controls on `compositions/azure-byoc`: `admin_group_object_ids`
  (managed-Entra RBAC; also disables the static-cert local admin accounts),
  `api_server_authorized_ip_ranges`, and `private_cluster_enabled`.
- Azure Blob/Key Vault firewall controls: `storage_network_default_action` and
  `key_vault_network_default_action` (default `Deny`), the `deployer_ip_ranges` /
  `workload_egress_ip_ranges` allow-lists, and plan-time reachability preconditions
  (with a mocked-provider `terraform test`) that fail fast on an unreachable deny-all.

### Changed
- Replaced the example customer placeholder name with a neutral `acme` across
  examples, docs, and generated module READMEs.
- Rewrote `docs/CONSUMING.md` as a beginner, step-by-step tutorial: what you end
  up with, a tools-to-install table, a permissions check (Azure role set — Owner or
  Contributor + User Access Administrator at subscription scope), resource-provider
  registration, region/quota notes, numbered per-cloud steps (sign in → clone →
  copy example → fill settings → bootstrap state → init → plan → apply → save
  outputs → verify), the app-install hand-off, the runner stage-2 inputs, teardown
  (Key Vault soft-delete behaviour), and a troubleshooting table. README and the
  example READMEs now point newcomers at it first.
- Designated Terraform as the canonical, tested CLI; the committed composition
  locks target the Terraform registry. OpenTofu still works but resolves from the
  OpenTofu registry and regenerates its own lock on `init`.
- Corrected the `[1.0.0]` `compositions/azure-byoc` changelog entry: it no longer
  claims managed Redis is provisioned or a Redis key is seeded (Redis runs
  in-cluster; only PG password/host/user are seeded), and the previously
  undocumented `modules/azure/external-secrets` is now listed.

### Fixed
- Federate the app workload identity to the chart's real app ServiceAccounts
  (`api-server-go`, `agents-py-http`, `agents-py-worker` in namespace `autoheal`).

## [1.0.0] - 2026-10-12

### Added
- Repo scaffold: module standard, consuming guide, CI gates, pre-commit, tflint.
- Cloud Posse null-label convention delivered via one shared base,
  `modules/_shared/label` (the harness-label equivalent; the single place
  `cloudposse/label/null` is pinned). `environment` redefined as lifecycle
  (`stage`/`prod`/`play`) and `stage` dropped from `label_order`.
- `modules/azure/vnet` — VNet, subnets (AKS, PG-delegated, private-endpoint,
  Redis-injected, runner), runner NAT gateway, PG private DNS zone, optional
  privatelink zones for Blob/Key Vault/Foundry.
- `modules/azure/postgres-flexible` — provisioned, private (VNet-integrated)
  PostgreSQL Flexible Server with the `azure.extensions` allow-list; consumes the
  vnet module's delegated subnet and PG private DNS zone.
- `modules/azure/blob` — Storage Account + private container; name sanitized from
  the label id (override available).
- `modules/azure/redis` — Azure Cache for Redis, Premium, injected into the vnet
  module's dedicated `snet-redis` (no Private Endpoint, no public endpoint). BYOC
  decision recorded: Premium + VNet injection, not Managed/Enterprise Redis.
- `modules/azure/keyvault` — RBAC-mode Key Vault with deployer Secrets Officer
  grant and optional seed secrets.
- `modules/azure/private-endpoint` — generic private endpoint (Blob/Vault/Foundry),
  instantiated per target via attributes.
- `modules/azure/acr` — Azure Container Registry (new; was script-created),
  keyless pulls, admin disabled.
- `modules/azure/workload-identity` — UAMI + federated credentials + Key Vault /
  Blob / ACR role grants (IRSA/Pod-Identity analogue).
- `modules/azure/external-secrets` — dedicated least-privilege UAMI for the External
  Secrets Operator (Key Vault Secrets User), federated to the ESO controller
  ServiceAccount; the composition wires it as `eso_identity`.
- `modules/azure/runner-vmss` — runner-go VMSS (Docker-out-of-Docker) with
  cloud-init, managed-identity AcrPull, NAT egress.
- `modules/azure/aks` — AKS cluster (create/connect), UAMI control plane, OIDC +
  workload identity, Cilium overlay, kubelet AcrPull.
- `compositions/azure-byoc` — wires the Azure modules into one install (resource
  group, generated PG password + host/user seeded to Key Vault, a dedicated
  External Secrets Operator identity, optional private endpoints) and emits the
  cross-cloud output contract. Redis runs in-cluster (app Helm chart), so it is
  not provisioned here. Runner VMSS is a separate post-Temporal apply.
- `examples/azure-byoc/terragrunt.hcl` — copyable Terragrunt wrapper (inputs +
  remote state) that consumers run.
- `compositions/azure-byoc-connect` — connect-mode (customer-provisioned infra) Azure install:
  reads existing VNet/AKS/PG/Key Vault/Redis/ACR/Storage via data sources, creates
  only the app workload identity (+ federated credentials, role grants) and optional
  seed secrets, and emits the identical output contract.
- `examples/azure-byoc-connect/terragrunt.hcl` — copyable Terragrunt wrapper for the
  connect-mode install.
- `modules/aws/vpc` — VPC, public/private subnets per AZ, per-AZ NAT gateways, and
  EKS discovery tags (`kubernetes.io/role/*`, `kubernetes.io/cluster/<name>=shared`).
  Azure analogue of `azure/vnet`.
- `modules/aws/rds-cluster` — Aurora PostgreSQL, provisioned (BYOC policy, NOT
  Serverless v2); writer + optional multi-AZ reader, SG-gated on the EKS primary
  security group. Azure analogue of `azure/postgres-flexible`.
- `modules/aws/elasticache` — ElastiCache Redis replication group, node-based, in-
  transit + at-rest encryption, SG-gated; automatic failover + Multi-AZ when >1 node.
  Azure analogue of `azure/redis`.
- `modules/aws/s3` — attachments bucket: versioned, SSE-S3, public access blocked,
  noncurrent-version expiry, optional CORS. Azure analogue of `azure/blob`.
- `modules/aws/secrets-manager` — connection secrets created under a shared prefix;
  storage only (read is granted by IRSA). Azure analogue of `azure/keyvault`.
- `modules/aws/ecr` — per-service repositories under the account registry with a
  lifecycle-prune policy; exposes the registry endpoint. Azure analogue of `azure/acr`.
- `modules/aws/eks` — EKS cluster, managed node group, IRSA OIDC provider, EBS CSI
  add-on; trimmed to BYOC essentials (no ALB-controller IAM). Azure analogue of
  `azure/aks`.
- `modules/aws/irsa` — app IAM role federated to the cluster OIDC provider with
  scoped Secrets Manager + S3 access; the cross-cloud `runner_identity`. Azure
  analogue of `azure/workload-identity`.
- `modules/aws/runner-asg` — runner-go EC2 Auto Scaling Group (Docker-out-of-Docker)
  with cloud-init, ECR credential-helper pulls via instance profile, SSM access; a
  separate post-Temporal apply. Azure analogue of `azure/runner-vmss`.
- `compositions/aws-byoc` — wires the AWS modules into one install (VPC, EKS, Aurora,
  ElastiCache, S3, ECR, generated PG password seeded to Secrets Manager, app IRSA)
  and emits the cross-cloud output contract. Runner ASG is a separate post-Temporal
  apply.
- `examples/aws-byoc/terragrunt.hcl` — copyable Terragrunt wrapper (inputs + S3
  remote state) that consumers run.
- Naming decision: null-label ids (`<namespace>-<environment>-<name>`) are
  canonical repo-wide; `*_override` inputs remain for fixed corporate schemes.
