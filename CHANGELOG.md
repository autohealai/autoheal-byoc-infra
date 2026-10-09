# Changelog

All notable changes to this repo are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/). One version covers the whole repo.

## [Unreleased]

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
- `modules/azure/runner-vmss` — runner-go VMSS (Docker-out-of-Docker) with
  cloud-init, managed-identity AcrPull, NAT egress.
- `modules/azure/aks` — AKS cluster (create/connect), UAMI control plane, OIDC +
  workload identity, Cilium overlay, kubelet AcrPull.
- `compositions/azure-byoc` — wires the Azure modules into one install (resource
  group, generated PG password + Redis key seeded to Key Vault, Redis, optional
  private endpoints) and emits the cross-cloud output contract. Runner VMSS is a
  separate post-Temporal apply.
- `examples/azure-byoc/terragrunt.hcl` — copyable Terragrunt wrapper (inputs +
  remote state) that consumers run.
- Naming decision: null-label ids (`<namespace>-<environment>-<name>`) are
  canonical repo-wide; `*_override` inputs remain for fixed corporate schemes.
