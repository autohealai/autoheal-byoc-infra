# compositions/aws

The AWS infrastructure for Autoheal, in one composition for every case: we
create everything, you bring everything, or a mix. Each building block takes an
optional `existing_*` input. Leave it empty and we create the resource; set it
and we read the resource with a data source and never change it.

The composition does not install the chart. It outputs `autoheal_values` (the
chart's infra values) and `cluster` (how to reach the cluster), which
`compositions/app` takes as inputs. See `examples/aws` for a complete
deployment repository. The structure, inputs and outputs follow
`compositions/azure`.

## Files

One file per building block.

| File | Creates, or reads when brought |
|------|--------------------------------|
| `network.tf` | VPC with private, data and public subnets per zone, NAT gateways, flow logs, the S3 gateway endpoint and optional interface endpoints. Brought: `existing_network`. |
| `kms.tf` | One customer managed key per purpose (eks, data, storage, secrets, logs), rotation on. Brought: `existing_kms_key_arn`, one key for all. |
| `cluster.tf` | EKS with access entries, Secrets envelope encryption, control plane logs, a managed node group and the add-ons (VPC CNI, CoreDNS, kube-proxy, Pod Identity agent, EBS CSI driver, Secrets Store CSI driver with the AWS provider). Brought: `existing_eks_cluster_arn`. |
| `postgres.tf` | Aurora PostgreSQL and its admin password. Brought: `existing_postgres_arn` (Aurora cluster or RDS instance). |
| `redis.tf` | ElastiCache for Valkey with TLS and an AUTH token. Brought: `existing_redis_arn`. |
| `storage.tf` | The attachments, artifacts and tenant buckets. Brought: `existing_attachments_bucket_arn`, `existing_artifacts_bucket_arn`. |
| `registry.tf` | ECR pull-through cache of the public Autoheal registry, only with `create_registry = true`. Brought: `existing_registry_url`. |
| `identity.tf` | IAM roles, one per chart workload group, bound to the chart's service accounts through EKS Pod Identity. |
| `secrets.tf` | Every secret the chart reads, generated or passed in, written to Secrets Manager. |
| `load-balancers.tf` | The edge Network Load Balancer, in `loadbalancer` mode. |
| `dns.tf` | Records for the three hostnames in your Route 53 zone. |
| `validation.tf` | Plan-time checks with plain messages. |
| `autoheal-values.tf` | The `autoheal_values` hand-off to the chart. |

## Cases

| Case | Inputs |
|------|--------|
| 1. We create everything | `account_id`, `region`, `network_cidr`, `existing_dns_zone_id` (or `create_dns_records = false`) |
| 2a. You bring everything, our Terraform runs | `existing_network` and every `existing_*` input, often `create_pod_identity_associations = false` |
| 3. Mixed | `existing_network` and `existing_dns_zone_id`; we create the rest |

Impossible mixes stop the plan with a message saying what to change, for example
a brought cluster without `existing_network` or in another VPC, an ARN in
another region or account, a PostgreSQL engine older than 15, a Redis in cluster
mode or with AUTH off, a bucket in another region, a KMS key that is not
symmetric, a hostname outside the zone, or a VPC with no NAT gateway and no
interface endpoints.

We change no security group of a brought database or Redis.
`required_datastore_owner_actions` lists the rule its owner adds so the pods can
connect.

The provider refuses to run with credentials for any account other than
`account_id`.

## Network

The VPC we create has one subnet of each kind per zone (2 to 4 zones, default
the first three of the region). For a /16:

| Subnets | CIDRs | Holds |
|---------|-------|-------|
| private | the first eighths, 10.60.0.0/19, 10.60.32.0/19, ... | nodes, pods (VPC CNI), an internal edge load balancer |
| data | 10.60.136.0/24, ... | Aurora, ElastiCache |
| public | 10.60.144.0/24, ... | NAT gateways, an internet-facing edge load balancer |

`nat_gateway_mode` is `per_az` by default, so a zone outage does not cut egress
for the other zones; `single` is cheaper. `none` removes internet egress: it
needs `private_endpoints_enabled = true` and a registry. VPC flow logs go to
CloudWatch, encrypted with the logs key.

In a brought network, `existing_network` names the VPC, at least two private
subnets and optionally data and public subnets and the node security group.
The subnets need no load balancer tags: Terraform creates the edge load
balancer, not the controller.

## Load balancers

In `loadbalancer` mode the edge Network Load Balancer is created in this apply,
so its DNS name is known before the chart is installed:

| Listener | Target | Health check |
|----------|--------|--------------|
| 443 | proxy pods on 8443 (TLS ends at the proxy) | TCP |
| 80 | proxy pods on 8090 (its redirect listener) | TCP |

The chart binds the proxy Service to the target groups with `TargetGroupBinding`
resources (`global.infra.targetGroups`), and the AWS Load Balancer Controller
registers the pod IPs. The controller does not create load balancers or
security groups. The load balancer has its own security group, and the node
security group gets ingress from it on the target ports only. In a brought
cluster these rules are added to `existing_network.node_security_group_id`, or
to the cluster security group when that is empty.

In the other edge modes we create no load balancer, and the cluster needs no
AWS Load Balancer Controller.

## Edge modes

| `edge_mode` | DNS records point at | `global.infra.targetGroups` |
|-------------|----------------------|-----------------------------|
| `loadbalancer` (default) | the edge Network Load Balancer (alias records) | `edgeHttps` (443 to the proxy's 8443) and `edgeHttp` (80 to 8090) |
| `gateway-api`, `istio`, `ingress` | `edge_address`; listed in `required_dns_records` while it is empty | not set |
| `none` | nothing; no records | not set |

The default needs nothing in the cluster besides the AWS Load Balancer
Controller: no Ingress controller, Gateway or Istio. The other modes are for a
cluster that already runs one and should front Autoheal too; the chart then
creates the Ingress, HTTPRoute or Istio resources, and `edge_address` is the
address of that entry point.

In `loadbalancer` mode TLS ends at the proxy, with `tls_certificate`.
`edge_exposure` picks an `internal` load balancer (default, reachable from the
VPC CIDR or `edge_allowed_cidr_blocks`) or an `internet-facing` one in the
public subnets, which needs `edge_allowed_cidr_blocks`.

## Workload roles

Each chart workload group gets its own IAM role, bound to its service accounts
with an EKS Pod Identity association. No pod uses the node role (IMDSv2 hop
limit 1) and no long-lived AWS key exists anywhere.

| Role | Service accounts | Can |
|------|------------------|-----|
| secrets | `autoheal-hooks` | read `<secrets_prefix>*` and decrypt with the secrets key |
| api-server | `api-server-go` | read and write the three buckets; keep the tenant bucket's versioning and lifecycle rules (and create it when `create_tenant_bucket = false`); manage secrets under `<runtime_secrets_prefix>/`; Bedrock |
| agents-worker | `agents-py-http`, `agents-py-worker` | read and write the three buckets; Bedrock |
| lb-controller | `kube-system/aws-load-balancer-controller` | describe load balancers and network state; register targets in the edge load balancer's target groups only |

Bedrock (`InvokeModel`, `InvokeModelWithResponseStream`) is on by default, on
every foundation model and inference profile in the account
(`bedrock_resource_arns` narrows it). The lb-controller role is created in
`loadbalancer` mode with a cluster we create; a brought cluster's own controller
needs `elasticloadbalancing:RegisterTargets` on our target groups.

With `create_pod_identity_associations = false` the roles are created and
`required_role_assignments` lists the associations as `aws eks
create-pod-identity-association` commands for an administrator. The workloads
cannot reach AWS until they exist. `iam_permissions_boundary_arn` is attached to
every role we create.

## Cluster access

The EKS cluster we create uses access entries only (no `aws-auth` ConfigMap).
The identity that runs the apply is cluster admin. Everyone else is listed:

| Input | Access policy | For |
|-------|---------------|-----|
| `cluster_admin_sso_permission_sets` | AmazonEKSClusterAdminPolicy | IAM Identity Center permission sets, by name, e.g. `AutohealAdmin` |
| `cluster_viewer_sso_permission_sets` | AmazonEKSViewPolicy | permission sets for on-call and audit; workloads and pod logs, no Secrets |
| `cluster_admin_principal_arns` | AmazonEKSClusterAdminPolicy | IAM roles or users by ARN, e.g. a break-glass role |
| `cluster_viewer_principal_arns` | AmazonEKSViewPolicy | IAM roles or users by ARN |

A permission set shows up in each account it is assigned to as a role named
`AWSReservedSSO_<name>_<random suffix>` under `/aws-reserved/sso.amazonaws.com/`.
The plan looks the role up by the permission set name and stops when it finds
none (the permission set is not assigned to `account_id`) or more than one. The
suffix never goes into a file, and when the role is recreated the next apply
replaces its access entry.

A brought cluster's access is its owner's: these inputs are ignored, and
`required_cluster_owner_actions` lists what the deployer needs.

## Secrets Manager entries

Written in the same apply as `<secrets_prefix><entry>` (default
`<namespace>-<environment>-<name>/`), encrypted with the secrets key. The names
are the chart's defaults, the list in the chart's `docs/secrets.md`. The chart's
secrets-sync hook Job and CronJob, running as `autoheal-hooks` with the secrets
role, copy them into Kubernetes Secrets through the Secrets Store CSI driver
with the AWS provider.

| Entry | Source |
|-------|--------|
| `postgres-admin-password` | Generated for a cluster we create; `postgres_admin_password` for a brought one |
| `api-server-db-password`, `agents-db-password`, `temporal-db-password`, `zitadel-db-password` | Generated |
| `api-server-database-url` | Built from the host and the generated `app_user` password, `sslmode=require` |
| `api-server-jwt-secret`, `zitadel-master-key`, `auth-app-session-secret`, `first-admin-password` | Generated |
| `oauth-encryption-key`, `oauth-state-signing-key` | Generated: base64 of 32 random bytes |
| `tool-response-server-secret` | Generated: 64 letters and digits |
| `redis-access-key`, `api-server-redis-url` | The AUTH token, generated for a Redis we create or `redis_auth_token`, when there is Redis. The URL is `rediss://:<token>@<host>:<port>/0`. |
| `llm-api-key` | `llm_api_key`, when set. Not needed for Bedrock. |
| `gateway-api-key`, `gateway-extra-headers` | `llm_gateway_api_key`, `llm_gateway_extra_headers`, when set; as in `compositions/azure` |
| `sso-client-secret` | `sso_client_secret`, when set |
| `tls-certificate`, `tls-private-key` | `tls_certificate`, when set |
| `edge-ca-certificate` | `edge_ca_certificate`, when set. `autoheal_values` then suggests `global.edge.tls.caVaultEntry`. |
| `github-app-private-key` | `github_app_private_key` (PEM), stored base64-encoded, when set |
| `github-app-webhook-secret` | `github_app_webhook_secret`, when set |

Generated values are kept across upgrades. A deleted secret stays recoverable
for `secrets_recovery_window_in_days` (default 30), which also blocks a new
secret with the same name: use 0 for throwaway installs.

## Runtime secrets

api-server-go stores the integration credentials users enter in the product in
Secrets Manager (`SECRET_MANAGER_PROVIDER=awssecretsmanager`), named
`<runtime_secrets_prefix>/tenants/<tenant>/...` with the default
`aws/secretsmanager` key. The prefix defaults to
`<namespace>-<environment>-<name>-runtime`, apart from the install prefix so the
api-server role cannot read the install secrets and the secrets role cannot read
runtime ones; the plan stops when they overlap. The prefix cannot change after
install, since existing secrets would no longer be found. The chart reads it
from `global.infra.runtimeSecrets`.

## Object storage

| Bucket | Name | Used for |
|--------|------|----------|
| attachments | `<id>-attachments` or `attachments_bucket_name` | chat attachments, with CORS for `https://<hostname>` |
| artifacts | `<id>-artifacts` or `artifacts_bucket_name` | investigation artifacts |
| tenant | `<tenant_bucket_prefix><tenant_id>` | the Git Registry and tool outputs |

Every bucket we create has the public access block, BucketOwnerEnforced, SSE-KMS
with the storage key and a bucket key, versioning, a TLS-only policy, aborted
multipart cleanup and expiry of old versions after
`s3_noncurrent_version_expiration_days`. api-server-go adds the Git Registry
lifecycle rules to the tenant bucket at startup, so Terraform leaves its rules
alone. `tenant_bucket_prefix` defaults to `<namespace>-<environment>-<name>-`;
it is 8 to 27 characters (a bucket name is at most 63 and the tenant ID 36, and
the api-server role may use every bucket named `<prefix>*`) and cannot change
after install. S3 names are global, so a name taken in another
account fails the apply.

## Encryption

With no `existing_kms_key_arn` we create five keys, one per purpose, with
rotation on and a 30 day deletion window. The key policy keeps the account root
statement, so IAM policies in this account grant use; `kms_key_administrator_arns`
can manage the keys without using them. The logs key also lets CloudWatch Logs
in this region use it. A brought key is used for all five purposes and must
allow the same.

## Registry and images

With `create_registry = true` we create an ECR pull-through cache of
`public.ecr.aws/e4h3h0d9` under `registry_repository_prefix`. Images are copied
into the account on first pull, so the install keeps running when the public
registry is unreachable. `autoheal_values` then suggests
`global.imageRegistry = <account>.dkr.ecr.<region>.amazonaws.com/<prefix>/e4h3h0d9`
and the matching Temporal and Zitadel repositories. With `existing_registry_url`
the chart pulls from your mirror, which must hold the images under `app/` and
`external/`. With neither the chart pulls from `public.ecr.aws/e4h3h0d9`.

## Outputs

| Output | Contents |
|--------|----------|
| `autoheal_values` | The chart's infra values (below). Pass to `compositions/app` as `infra_values`. |
| `autoheal_values_yaml` | The same as YAML, for a Helm or Flux install. |
| `cluster` | `cloud`, `name`, `region`, `endpoint`, base64 `ca_certificate`, `vpc_id`. No credential. |
| `required_role_assignments` | Pod Identity association commands for an administrator, filled when `create_pod_identity_associations = false`. |
| `required_dns_records` | Records for a person to create (`name`, `type`, `value`), filled when we do not create them. |
| `required_cluster_owner_actions` | What the owner of a brought cluster must do, as readable lines: an access entry and IAM permissions for the deployer, the Pod Identity agent and Secrets Store CSI add-ons, and, when they apply, the AWS Load Balancer Controller (`loadbalancer` mode), a path to a private API endpoint and image pull access for the nodes. Filled only with `existing_eks_cluster_arn`. |
| `required_datastore_owner_actions` | What the owner of a brought database or Redis must do: a security group rule letting the pods in on its port. Filled only with `existing_postgres_arn` or `existing_redis_arn`. |
| `network` | `vpc_id`, `vpc_cidr_block`, `private_subnet_ids`, `data_subnet_ids`, `public_subnet_ids`. |

`autoheal_values` keys:

```text
global.infra.version                          infra contract version, 3.0.0
global.infra.cloud                            aws
global.infra.region
global.infra.hosts.{app,auth,authApp}
global.infra.secretsManager.prefix            install secret <e> is <prefix><e>
global.infra.runtimeSecrets.{kind,region,prefix}   awssecretsmanager, no trailing slash
global.infra.database.{host,port,adminUser,adminPasswordVaultEntry}
global.infra.redis.{host,port}                when there is Redis
global.infra.objectStore.{kind,bucket,artifactsBucket,tenantBucketPrefix}
global.infra.targetGroups.{edgeHttps,edgeHttp}   loadbalancer mode only
global.imageRegistry                          suggestion, with a registry
global.addons.install                         suggestion: false, the EKS add-ons provide the CSI driver
global.secrets.mode                           suggestion: keyvault-csi
global.edge.mode                              suggestion: edge_mode
global.edge.tls.caVaultEntry                  suggestion: edge-ca-certificate, when edge_ca_certificate is set
global.llm.gateway.*                          as in compositions/azure
temporal.server.config.persistence.{default,visibility}.sql.host   copy of the database host
zitadel.zitadel.configmapConfig.ExternalDomain                     copy of hosts.auth
zitadel.zitadel.configmapConfig.Database.Postgres.Host             copy of the database host
temporal.*.image.repository, zitadel.image.repository, zitadel.login.image.repository, zitadel.imageRegistry   with a registry
```

None of the outputs holds a secret.

## Tests

```bash
terraform init -backend=false
terraform test
```

`tests/` plans each case against mocked providers: `create.tftest.hcl` (case 1,
each edge mode, the optional blocks and cluster access), `bring.tftest.hcl`
(case 2, the hybrid case, each guard on a brought resource and the owner's
actions for a brought cluster) and `validation.tftest.hcl` (the plan-time checks
on inputs).
