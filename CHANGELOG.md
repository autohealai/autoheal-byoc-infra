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
- `compositions/azure-byoc-connect` — connect-mode (Nomura-style) Azure install:
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
