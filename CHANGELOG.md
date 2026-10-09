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
