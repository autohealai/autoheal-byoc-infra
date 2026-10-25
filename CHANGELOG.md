# Changelog

All notable changes to this repo are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[SemVer](https://semver.org/). One version covers the whole repo.

## [Unreleased]

## [4.0.0] - 2026-10-24

Breaking: 4.0.0. This repository no longer creates the sandbox runner, on
Azure or AWS. The runner VMs, the reserved Temporal address and everything that
existed only for them are gone. Sandboxes do not run on an install from this
release until a runner runs elsewhere.

Needs: autoheal chart 1.0.0-rc.11 or later. It turns
`temporalFrontendLoadBalancer` and `toolResponseLoadBalancer` off by default and
adds `global.sandbox.enabled`, off by default. Chart 1.0.0-rc.10 and older
refuse the 4.0.0 infra values: they require `temporal.internalIP` on Azure, and
`global.infra.targetGroups.temporal` and `toolResponse` on AWS. A new install
applies the infra first, as before. An upgrade installs the new chart before
the 4.0.0 infra apply; see "Upgrading from 3.x" below.

Keep `global.sandbox.enabled` off until a runner runs elsewhere. With it on and
no runner, every agent run waits for a sandbox that never starts, then fails
after about 11 minutes. Off, the agents answer and call integrations but run
no commands.

### Removed
- Azure: `modules/azure/runner-vmss`, and from `compositions/azure` the runner
  VMSS, its identity grants, the runner subnet, its NAT gateway and NSG, the
  SSH key, and the NSG on the AKS subnet that only allowed the runner to reach
  Temporal. On the public path (cluster in another subscription with no private
  network) the VNet existed only for the runner and is not created.
- AWS: `modules/aws/runner-asg`, and from `compositions/aws` the runner Auto
  Scaling group, its launch template, role and security group, the runner
  subnets of the VPC we create, and the internal load balancer the runner
  used (Temporal on 7233, the api-server-go tool results listener on 8083).
- Inputs: `autoheal_version`, `runner_image_repository`, `runner_image_tag`,
  `runner_sandbox_image`, `runner_node_count`, `runner_max_concurrent_activities`;
  Azure `runner_vm_size`, `runner_os_disk_size_gb`, `runner_admin_ssh_public_key`,
  `existing_network.runner_subnet_id` and `existing_network.temporal_ip`; AWS
  `runner_instance_type`, `runner_architecture`, `runner_root_volume_size_gb`
  and `existing_network.runner_subnet_ids`. Delete them from your inputs.
  Terraform ignores the old `existing_network` attributes, and ignores or warns
  about the old variables, depending on how they are passed.
- `modules/aws/vpc`: the `runner_subnet_cidrs` input and the `runner_subnet_ids`
  output.
- Outputs: `temporal_public_endpoint` (Azure) and `network.runner_subnet_id`
  (Azure) / `network.runner_subnet_ids` (AWS). `compositions/app` no longer
  takes `temporal_public_endpoint`.
- `autoheal_values`: the runner load balancer values (`temporal.internalIP` and
  the suggested `temporalFrontendLoadBalancer` and `toolResponseLoadBalancer`
  on Azure, the `temporal` and `toolResponse` target groups on AWS). AWS
  `global.infra.targetGroups` is present only with `edge_mode = "loadbalancer"`.

### Changed
- `global.infra.version` (the infra contract) is 3.0.0 on both clouds.
- AWS: the AWS Load Balancer Controller role is created only with
  `edge_mode = "loadbalancer"`. In the other modes
  `create_load_balancer_controller_role` is ignored, and an apply destroys a
  role made before. `required_cluster_owner_actions` lists the controller and
  the node security group ingress only in that mode.
- Azure, cluster you bring (`existing_aks_cluster_id`): `compositions/azure`
  never reads it. It takes only the name and resource group from the ID, needs
  no access to the cluster's subscription (the `azurerm.cluster` provider is
  gone), and makes no federated credentials. Its `cluster` output has an empty
  endpoint and CA certificate, and a new `federation` output lists the
  identities to federate.
- Azure, cluster you bring: the checks that needed to read the cluster or its
  subnet are gone: that `existing_network.proxy_ip` is inside the AKS subnet,
  and the AcrPull grant for the kubelet identity. `required_cluster_owner_actions`
  lists the AcrPull grant instead.
- Azure, public path: the storage account ignores its subnet network rules. The
  cluster owner adds the rule for the AKS subnet with the command in
  `required_cluster_owner_actions`, and later applies leave it alone.
- Examples: `examples/azure/split` and `examples/azure/split-public` have a
  `cluster` folder between `infra` and `app`, and `app` takes `cluster` from
  it. `examples/azure/cop-standin` no longer makes the runner subnet, the
  Temporal address or the grants they needed.

### Added
- `compositions/azure-cluster`: the cluster step for an AKS cluster you bring.
  It reads the cluster in its own subscription, stops when the OIDC issuer is
  off, warns when the Key Vault secrets provider add-on is off, creates one
  federated credential per chart service account, and outputs `cluster` with
  the endpoint and CA certificate for `compositions/app`.
  `import_federated_credentials` adopts the credentials 3.x made.

### Fixed
- `compositions/aws` tests pass on OpenTofu 1.11. The mocks give well-formed IDs
  and ARNs; before, OpenTofu filled them with random strings that the
  validation rules rejected.

### Upgrading from 3.x
1. Install the new chart, still on the 3.x infra values. Its defaults turn the
   runner load balancers and sandboxes off. Until step 2, it warns about the
   runner values in the infra values, which it ignores.
2. Delete the removed inputs and apply the infra unit. The plan destroys the
   runner and the resources listed under Removed. With a brought AKS cluster it
   also destroys the federated credentials, unless you move them first (see
   `compositions/azure-cluster/README.md`).
3. Brought AKS cluster: apply `compositions/azure-cluster` (the new `cluster`
   folder), then point the app unit's `cluster` at it.
4. Apply the app unit.

## [3.0.0] - 2026-10-21

AWS moves to the 2.x shape: `compositions/aws` replaces the 1.x
`compositions/aws-byoc`, with the same two-folder layout, `existing_*` inputs
and outputs as `compositions/azure`. Azure installs see no change: the plan is
the same as on 2.2.1, and the Azure `global.infra` keeps contract version
2.0.0. Major version because `compositions/aws-byoc`, `examples/aws-byoc` and
the 1.x AWS modules' interfaces are gone.

Needs, on AWS: autoheal chart 1.0.0-rc.9 or later. It accepts
`global.infra.cloud: aws` (contract 2.1.0) and carries api-server-go 0.7.701,
which reads `TENANT_BUCKET_PREFIX` and `SECRET_MANAGER_AWS_SECRET_PREFIX`.
Older api-server-go images name tenant buckets and runtime secrets outside what
the IAM roles allow.

### Added
- `compositions/aws`: one AWS composition for every case. Each building block
  (network, EKS cluster, Postgres, Redis, the attachments and artifacts
  buckets, the KMS key, the registry) takes an optional `existing_*` input:
  empty means we create it, set means we read it with a data source and never
  change it. Impossible mixes and unsuitable brought resources (a cluster in
  another VPC, PostgreSQL older than 15, ElastiCache in cluster mode, a bucket
  in another region, an asymmetric key, ARNs in another account or region) stop
  the plan with plain messages (`validation.tf`).
- `compositions/aws`: a VPC over two to four zones (three by default) with
  public, private, data and runner subnets, a NAT gateway per zone (or one, or
  none with `private_endpoints_enabled`), VPC flow logs, an S3 gateway endpoint
  and optional interface endpoints.
- `compositions/aws`: EKS with a managed node group, access entries,
  envelope encryption of Kubernetes secrets,
  control plane logs, and the managed add-ons the chart needs
  (`eks-pod-identity-agent`, `aws-secrets-store-csi-driver-provider`,
  `aws-ebs-csi-driver`, plus the defaults). `api_server_authorized_ip_ranges`
  or `private_cluster_enabled` limit who reaches the API.
- `compositions/aws`: Aurora PostgreSQL (provisioned or Serverless v2) with a
  writer and a reader, 30-day backups, deletion protection and TLS only;
  ElastiCache (Valkey) with a replica, Multi-AZ failover, TLS and a generated
  AUTH token, or `redis_enabled = false`.
- `compositions/aws`: S3 buckets for attachments and artifacts, and for the
  tenant Git Registry `<tenant_bucket_prefix><tenant id>` (`tenant_id`,
  `create_tenant_bucket`), versioned, TLS only, with optional access logs.
- `compositions/aws`: customer managed KMS keys with rotation, one each for EKS
  secrets, the data stores, S3, Secrets Manager and logs, or one brought key
  for all (`existing_kms_key_arn`).
- `compositions/aws`: every secret the chart reads, generated or passed in and
  written to Secrets Manager under `secrets_name_prefix`, with the entry names
  of the Azure composition plus `redis_auth_token` for a brought Redis with
  AUTH. Runtime secrets go under `runtime_secrets_name_prefix`, which only the
  api-server role may manage; the two prefixes may not overlap.
- `compositions/aws`: one IAM role per chart role (secrets, api-server,
  agents-worker) bound to the chart's service accounts with EKS Pod Identity,
  and a role for the AWS Load Balancer Controller limited to registering
  targets in our target groups. `create_pod_identity_associations = false`
  lists the associations in `required_role_assignments` instead.
  `iam_permissions_boundary_arn` applies to every role. `bedrock_access_enabled`
  lets the agents and api-server roles call Bedrock.
- `compositions/aws`: NLBs with ip target groups for the edge (443 and 80, in
  `loadbalancer` mode, internal or internet-facing with
  `edge_allowed_cidr_blocks`), Temporal (7233) and the tool response listener
  (8083). `autoheal_values` passes their target group ARNs to the chart, which
  binds its Services with `TargetGroupBinding`.
- `compositions/aws`: Route 53 records for the three hostnames in an existing
  hosted zone (`existing_dns_zone_id`), or `required_dns_records`.
- `compositions/aws`: an ECR pull-through cache of the public Autoheal registry
  (`create_registry`), or `existing_registry_url`.
- `compositions/aws`: the runner instances (`modules/aws/runner-asg`) in the
  same apply, pulling `app/runner-go:chart-<autoheal_version>`.
- `compositions/aws`: outputs `autoheal_values`, `autoheal_values_yaml`,
  `cluster` (with `region` and `vpc_id`), `required_role_assignments`,
  `required_dns_records` and `network`, as on Azure. `global.infra` is contract
  version 2.1.0, which adds the AWS keys.
- `compositions/app`: `aws_load_balancer_controller` installs the AWS Load
  Balancer Controller (chart 3.6.0) in `kube-system` before the Autoheal chart,
  on EKS only. `cluster.vpc_id` is a new optional input for it.
- `examples/aws`: the deployment repository to copy, like `examples/azure`.
- `scripts/bootstrap-state-aws.sh`: creates the S3 state bucket (versioning,
  encryption, TLS only, public access blocked). `examples/aws/root.hcl` locks
  state with `use_lockfile`, so no DynamoDB table.
- `modules/aws/aurora-postgres`, `modules/aws/kms`, `modules/aws/nlb`,
  `modules/aws/pod-identity` and `modules/aws/route53`.
- `compositions/aws`: who may use the cluster we create. Admins
  (`AmazonEKSClusterAdminPolicy`) and viewers (`AmazonEKSViewPolicy`, no
  Secrets) by IAM ARN (`cluster_admin_principal_arns`,
  `cluster_viewer_principal_arns`) or by IAM Identity Center permission set
  (`cluster_admin_sso_permission_sets`, `cluster_viewer_sso_permission_sets`).
  A permission set is resolved to the `AWSReservedSSO_<name>_<suffix>` role in
  the account at plan time, and the plan stops when it is not assigned there
  or a principal is listed twice.
- `compositions/aws`: the `required_cluster_owner_actions` output. For a
  brought cluster it lists what the cluster's owner must do, with the names
  filled in: the deployer's access entry and IAM permissions, the Pod Identity
  and Secrets Store CSI add-ons, the AWS Load Balancer Controller and, when
  they apply, a path to a private API endpoint and image pull access. Same name
  as in `compositions/azure`.
- `examples/aws`: IAM Identity Center access with an SSO profile and a
  break-glass role, the pipeline's OIDC role trusted only from the prod
  environment, the edge modes (`loadbalancer` needs no Ingress controller) and
  the LLM gateway block.
- Tests for `compositions/aws` (`create`, `bring` and `validation`, against
  mocked providers).

### Changed
- `examples/azure/*/versions.hcl`, the README and the docs pin v3.0.0. The
  Azure examples stay on chart 1.0.0-rc.8.
- `modules/aws/vpc`: `cidr_block` replaces `vpc_cidr`. Adds data and runner
  subnet tiers, `nat_gateway_mode`, flow logs and VPC endpoints.
- `modules/aws/eks`: `subnet_ids` replaces `private_subnet_ids` and
  `public_subnet_ids`; `secrets_kms_key_arn` replaces `kms_key_arn`;
  `enabled_log_types` replaces `enabled_cluster_log_types`; the name comes from
  the label instead of `cluster_name`. Adds access entries, an `addons` map,
  node disk, AMI and repair settings, and upgrade support type. No IAM OIDC
  provider: workloads use Pod Identity.
- `modules/aws/elasticache`: `allowed_security_group_ids` and
  `allowed_cidr_blocks` replace `allowed_sg_ids` and `vpc_cidr_block`. Adds
  `engine`, AUTH, a CMK, Multi-AZ failover, logs and parameters.
- `modules/aws/s3`: `bucket` replaces `bucket_name_override`; `cors_rules` and
  `lifecycle_rules` replace the CORS and expiry inputs. Adds a CMK, access logs,
  `force_destroy` and an extra policy document.
- `modules/aws/secrets-manager`: `name_prefix`, `secret_names` and
  `secret_values` replace `secret_prefix` and `secrets`. Adds a CMK and replica
  regions.
- `modules/aws/ecr`: a pull-through cache rule (`upstream_registry_url`,
  `upstream_namespace`, `repository_prefix`) replaces per-service repositories.
- `modules/aws/runner-asg`: `ecr_registry_host` replaces `ecr_registry`; the
  group size is `instance_count` only (`min_size` and `max_size` are gone). Adds
  `tool_response_callback_url`, `architecture`, root volume settings, a
  permissions boundary and instance refresh settings. No SSH key.

- CI: Terraform providers are cached across the module, composition and
  example jobs, so a runner no longer runs out of disk.

### Removed
- `compositions/aws-byoc` and `examples/aws-byoc`. An install on them is not
  upgraded in place: install `compositions/aws` next to it and move the data.
- `modules/aws/irsa` (replaced by `modules/aws/pod-identity`) and
  `modules/aws/rds-cluster` (replaced by `modules/aws/aurora-postgres`).

## [2.2.1] - 2026-10-20

Docs and examples only. The modules and compositions are the same as 2.2.0, so
an install moving from 2.2.0 plans no changes.

### Fixed
- `examples/azure/*/app/values-customer.yaml`, `docs/getting-started.md` and
  step 11a of `docs/azure-two-subscriptions-public-runbook.md` set
  `global.llm.offeredModels`. Without it the chart gives api-server-go no
  `AGENT_SUPPORTED_MODELS`, and every agent run fails with "this deployment
  offers no models". Each example and doc pins v2.2.1.

## [2.2.0] - 2026-10-20

An AKS cluster in another subscription, over connected VNets or over public
endpoints, and a public Autoheal proxy. Installs that keep the cluster in `subscription_id`
change no Azure resource: the plan adds only
`terraform_data.validate_subscriptions`, a plan-time check, and the new output
values. The subnets in `modules/azure/vnet` move to `[0]` addresses through
`moved` blocks.

### Added
- `compositions/azure`: `existing_aks_cluster_id` may be in another
  subscription of the same Entra tenant. The cluster and its AKS subnet are
  read there through a second `azurerm` provider (`azurerm.cluster`) that only
  data sources use and that registers no resource providers, so nothing is
  created in that subscription. Every other resource goes in
  `subscription_id`. When `existing_network` names only the AKS subnet and the
  two reserved addresses, we create a VNet in `subscription_id` from
  `network_cidr` for the runner, Postgres and private endpoints, without an AKS
  subnet.
- `compositions/azure`: `cluster_network_path` (default `private`). With
  `public`, for a cluster in another subscription with no VNet connection: our
  VNet has only the runner subnet and its NAT gateway; Postgres has public
  access with a firewall rule per `workload_egress_ip_ranges` entry; the Key
  Vaults keep their IP firewall; storage also lets in the cluster's AKS subnet,
  since Azure Storage ignores IP rules from its own region; Redis has a public
  endpoint (Azure Managed Redis has no IP firewall); and
  `existing_network.temporal_ip` is a static public IP in the cluster's node
  resource group. `autoheal_values` then turns off the chart's internal
  Temporal and tool-response load balancers, and the new
  `temporal_public_endpoint` output carries the IP and the runner's NAT
  address. Temporal and tool results are not encrypted on that path.
- `compositions/app`: `temporal_public_endpoint` (default null) creates public
  load balancers for Temporal (7233) and the tool-response listener (8083) on
  the static IP, open only to the runner's NAT address, with a network policy
  for each.
- `compositions/azure`: `edge_exposure` (default `internal`). With `public`,
  for a brought cluster in loadbalancer mode, `existing_network.proxy_ip` is a
  Standard static public IP in the cluster's node resource group, so that users
  and webhooks reach the proxy from the internet; on `cluster_network_path =
  public` it may be `temporal_ip`, to use one IP for both. `autoheal_values` now
  sets `global.edge.exposure` in loadbalancer mode, so `values-customer.yaml`
  no longer sets it, and the DNS records point to the public IP.
  `required_cluster_owner_actions` lists the proxy's static IP and its NSG rule
  for TCP 443 and 80. `examples/azure/split-public` uses a public proxy.
- `compositions/azure`: `cluster_vnet_dns_link_enabled` (default false) also
  links the private DNS zones we create to the cluster's VNet in the other
  subscription. The deployer needs join permission on that VNet.
- `compositions/azure`: the `required_cluster_owner_actions` output, filled for
  a brought cluster: the deployer's roles on the cluster (Cluster User Role,
  Reader on the AKS subnet, RBAC Admin on the namespace), the namespace, the
  cluster features, the NSG rule for the Temporal address and, for a cluster in
  another subscription, the network path between the VNets, the user path to
  the proxy and private DNS.
- `compositions/azure`: `cluster.subscription_id` (the cluster's) and
  `network.cluster_vnet_id` in the outputs.
- `compositions/app`: `create_namespace` (default true). Set false when the
  deployer has rights in the release namespace only.
- `modules/azure/vnet`: `subnet_aks_prefix`, `subnet_db_prefix` and
  `subnet_pe_prefix` may be empty, to skip that subnet (and, for the AKS
  subnet, the NSG). The subnets move to `[0]` addresses with `moved` blocks,
  so existing networks plan no changes.
- `modules/azure/postgres-flexible`: `public_network_access_enabled` and
  `allowed_ip_ranges` for a server with public access and a firewall rule per
  range; the `firewall_rules` output.
- `modules/azure/blob`: `allowed_subnet_ids`, subnets let through the storage
  firewall.
- `modules/azure/managed-redis`: `public_network_access_enabled`.
- `examples/azure/split` (connected VNets) and `examples/azure/split-public`
  (public endpoints): the deployments for a cluster in another subscription.
  `examples/azure/cop-standin` is an internal stand-in for that cluster's
  subscription, for testing both (not for customers).
- `docs/azure-subscription-options.md`: one subscription, connected VNets and
  public endpoints compared on security, maintenance and cost.
  `docs/azure-two-subscriptions.md` and
  `docs/azure-two-subscriptions-public.md`: a one-page explanation of each
  two-subscription layout for the cluster owner.
  `docs/azure-two-subscriptions-public-runbook.md`: every command to install
  the public-endpoint layout on an existing AKS cluster, with Terragrunt and
  state in Azure Blob, or with Terraform Enterprise and a Helm install. All
  linked from `docs/getting-started.md`.

### Changed
- `compositions/azure`: the plan checks that the AKS subnet is in the
  cluster's subscription, and that the other brought subnets and
  `existing_resource_group_id`, `existing_postgres_id`, `existing_redis_id`,
  `existing_storage_account_id`, `existing_key_vault_id`,
  `existing_runtime_key_vault_id` and `existing_acr_id` are in
  `subscription_id`, as is `existing_dns_zone_id` when we create records.
  Before, the subscription in these IDs was ignored and the resource was looked
  up in `subscription_id`.
- `compositions/azure`: `existing_network.runner_subnet_id` is optional in the
  type. It is still required, with a plain message, except for a cluster in
  another subscription with no subnets given.
- `modules/azure/postgres-flexible`: `delegated_subnet_id` and
  `private_dns_zone_id` default to null.
- `compositions/azure`: `network.vnet_id`, `vnet_name`, `resource_group_name`
  and `address_space` describe the VNet of the runner and private endpoints.
  That is the same VNet as before unless the cluster is in another
  subscription.

## [2.1.1] - 2026-10-19

Docs and examples only. The modules and compositions are the same as 2.1.0, so
an install moving from 2.1.0 plans no changes.

### Fixed
- `examples/azure`: `prod/versions.hcl` pins chart `1.0.0-rc.8` instead of
  `1.0.0`, which is not published, so a copied example failed at the `prod/app`
  apply with "chart not found". The Helm commands in `examples/azure/README.md`
  and `docs/terraform-enterprise.md` use the same version.
- The pinned chart is `1.0.0-rc.8`, not `1.0.0-rc.7`. With rc.7, agents that
  write artifacts (reports, RCA documents) failed with "create_artifact failed:
  503 - durable object storage is not configured for this deployment". rc.8
  stores them in a `<container>-artifacts` container in the same storage
  account, which the app creates at startup. The existing role assignment
  covers it, so the infra plan does not change.
- `docs/getting-started.md`, `README.md`, `docs/terraform-enterprise.md` and
  `examples/azure/prod/versions.hcl` point at `v2.1.1`, so the guide copies the
  fixed example.

## [2.1.0] - 2026-10-18

Optional LLM gateway support on Azure. Installs that do not set the new inputs
see no change: the plan is the same as on 2.0.0, and `global.infra` keeps
contract version 2.0.0.

### Added
- `compositions/azure`: `llm_gateway_api_key` and `llm_gateway_extra_headers`
  (both sensitive, default empty) for installs that send model calls through an
  LLM gateway. Stored as the `gateway-api-key` and `gateway-extra-headers`
  vault entries when set. `llm_gateway_api_key` is needed for every gateway
  kind except `custom`; for a gateway that ignores it, such as Portkey OSS, set
  any value. `llm_gateway_extra_headers` must be a JSON object with at least one
  header, each value a string. When it is set, `autoheal_values` suggests
  `global.llm.gateway.extraHeadersVaultEntry`, plus an empty
  `global.llm.gateway.apiKeyVaultEntry` when `llm_gateway_api_key` is unset.
  These need autoheal chart 1.0.0-rc.3 or later; older charts reject
  `global.llm.gateway`.
- `docs/getting-started.md`: "Optional: an LLM gateway", how to send model calls
  through a gateway you run (Portkey OSS, hosted Portkey, LiteLLM and the other
  kinds the chart knows): which secrets to set for each, a Portkey OSS config,
  the `global.llm.gateway` block for `values-customer.yaml`, how embeddings go
  through the gateway, how to check that calls go through the gateway, and
  troubleshooting rows. `examples/azure`, `docs/terraform-enterprise.md` and
  the README point to it.
- `docs/getting-started.md` Step 7: the Azure OpenAI resource needs an
  embedding deployment named `text-embedding-3-large`, or
  `global.llm.embeddingModel` set to another one with 1024 dimensions.

### Changed
- `llm_api_key` is not needed with the chart's LLM gateway on, since the
  gateway holds the provider keys and the chart then does not read
  `llm-api-key`. The variable description, the secrets tables and the example
  comments say so.

### Fixed
- `examples/azure/prod/app/values-customer.yaml` and `docs/getting-started.md`:
  the Azure OpenAI endpoint is the v1 endpoint, ending in `/openai/v1/`.
  agents-py rejects the bare resource address the example showed.

## [2.0.0] - 2026-10-17

2.0.0, Azure first. `compositions/aws-byoc` and the AWS modules are unchanged.

### Added
- `compositions/azure`: one Azure composition for every case. Each building
  block (resource group, network, cluster, Postgres, Redis, storage, registry,
  Key Vault) takes an optional `existing_*` ID: empty means we create it, set
  means we read it with a data source and never change it. Impossible mixes stop
  the plan with plain messages (`validation.tf`).
- `compositions/azure`: `hostname`, `auth_hostname`, `auth_app_hostname`,
  `edge_mode` (`loadbalancer`, `gateway-api`, `istio`, `ingress`, `none`) and
  `edge_address`. DNS A records for the three hostnames in an existing zone
  (`existing_dns_zone_id`), or the `required_dns_records` output with
  `create_dns_records = false`. We never create the zone.
- `compositions/azure`: reserved internal addresses for Temporal and, in
  `loadbalancer` mode, the proxy. Computed in a network we create, taken from
  `existing_network.temporal_ip` and `proxy_ip` in a brought one.
- `compositions/azure`: the runner VMs (`modules/azure/runner-vmss`) in the same
  apply, pulling `<registry>/app/runner-go:chart-<autoheal_version>`. The
  registry is the composition's ACR when there is one, else
  `public.ecr.aws/e4h3h0d9`. `runner_image_repository` and `runner_image_tag`
  override the repository and the tag. The runners
  post sandbox tool results to
  `http://<temporal_ip>:8083/api/v1/internal/sandbox-tool-responses`, the
  api-server-go internal listener the chart puts on the Temporal address.
- `modules/azure/runner-vmss`: `tool_response_callback_url`, written to the
  runner's environment as `SANDBOX_TOOL_RESPONSE_CALLBACK_URL`.
- `modules/azure/vnet`: `temporal_ip`. When set, an NSG on the AKS subnet lets
  only the runner subnet reach that address on 7233 and 8083, and denies the
  two ports there from every other source. The composition sets it in a network
  it creates. Outputs `aks_nsg_id` and `aks_nsg_name`.
- `compositions/azure`: one workload identity per chart role (secrets,
  api-server, agents-worker), federated to the chart's service accounts
  (`service_accounts`). The secrets identity is federated to `autoheal-hooks`
  only, the service account of the chart's secrets-sync hook Job and CronJob.
- `compositions/azure`: every secret the chart reads is generated or passed in
  and written to the vault in the same apply, under the names in the chart's
  `docs/secrets.md`. Entries: `postgres-admin-password`,
  `api-server-db-password`, `agents-db-password`, `temporal-db-password`,
  `zitadel-db-password`, `api-server-database-url`, `api-server-jwt-secret`,
  `zitadel-master-key`, `auth-app-session-secret`, `first-admin-password`,
  `oauth-encryption-key`, `oauth-state-signing-key`,
  `tool-response-server-secret`, and when they apply `redis-access-key`,
  `api-server-redis-url`, `llm-api-key`, `sso-client-secret`, `tls-certificate`,
  `tls-private-key`, `edge-ca-certificate`, `github-app-private-key`,
  `github-app-webhook-secret`. New sensitive inputs: `postgres_admin_password`
  (required with `existing_postgres_id`), `llm_api_key`, `sso_client_secret`,
  `tls_certificate`, `github_app_private_key`, `github_app_webhook_secret`; and
  `edge_ca_certificate`. A generated runner SSH key stays in the state and is
  not written to the vault.
- `compositions/azure`: a runtime Key Vault for the integration credentials
  api-server-go stores (`SECRET_MANAGER_PROVIDER=azurekeyvault`), separate from
  the install vault so the api-server identity cannot read install secrets.
  Azure RBAC, same firewall and private endpoint as the install vault. The
  api-server identity gets Key Vault Secrets Officer on it. New inputs:
  `existing_runtime_key_vault_id`, `runtime_key_vault_soft_delete_retention_days`
  (default 90) and `runtime_key_vault_purge_protection_enabled` (default: the
  install vault's setting). `autoheal_values` gains
  `global.infra.runtimeSecrets = { kind = "azurekeyvault", vaultURL }`.
- `compositions/azure`: with a registry, `autoheal_values` suggests
  `global.imageRegistry` (the login server) and the matching Temporal and Zitadel
  image repositories under `<login server>/external/`, which the chart's
  validation requires.
- `compositions/azure`: `create_role_assignments`. With `false` no grant is
  made; the `required_role_assignments` output lists them for an administrator
  and the apply stops, naming the missing workload grants, until they exist.
- `compositions/azure` outputs: `autoheal_values` and `autoheal_values_yaml` (the
  chart's infra values: `global.infra`, the suggested `global.addons`,
  `global.secrets`, `global.edge` and `global.imageRegistry`, and the Temporal
  and Zitadel copies),
  `cluster`, `required_role_assignments`, `required_dns_records`, `network`
  (VNet and subnet IDs and the address space).
- `compositions/app`: installs the chart with one `helm_release` from the infra
  composition's `autoheal_values` and the customer's `values-customer.yaml`,
  atomic with wait. Logs in with `kubelogin` on AKS and `aws eks get-token` on
  EKS. `chart_repository` takes the public OCI registry (default), an HTTPS
  repository or a local chart path.
- `modules/azure/managed-redis`: Azure Managed Redis with public access off.
- `modules/azure/dns`: A records in an existing public or private zone.
- `modules/azure/aks`: `entra_integration_enabled` and
  `key_vault_secrets_provider_enabled` (both default `true`).
- `examples/azure`: a deployment repository with `root.hcl` (generated azurerm
  backend, Entra ID auth), `prod/versions.hcl`, `prod/infra` and `prod/app`.
- `scripts/bootstrap-state-azure.sh`: grants the signed-in identity Storage Blob
  Data Contributor on the state account, which `use_azuread_auth` needs.
- `tofu test` / `terraform test` suites for both compositions, passing on
  Terraform 1.9 and OpenTofu 1.11.

### Changed
- `modules/azure/external-secrets` is renamed `modules/azure/secrets-identity`.
  It is federated to the chart's service accounts and read by the Key Vault CSI
  driver; `role_assignment_enabled = false` leaves the grant to an administrator.
- `modules/azure/keyvault`: no longer seeds entries; the composition writes them.
- `modules/azure/runner-vmss`: `acr_id` and `acr_name` are optional. Without
  `acr_name` the VMs pull public images and install no Azure CLI.
  `acr_pull_enabled` gates the grant. The runner unit retries the image pull
  with a backoff (15 seconds, doubling up to 5 minutes) until it succeeds, with
  no systemd start limit, so the image can be pushed after the VMs boot.
- The runner image moves from `<registry>/runner-go` to
  `<registry>/app/runner-go`, the chart's image layout.
- `modules/azure/runner-vmss`: the runner VMs match Autoheal's hosted runners.
  The OS disk defaults to 1024 GiB (Premium SSD P30, 5000 IOPS) instead of 200
  GiB (P15, 1100 IOPS): after a boot the runner clones the data-source repos and
  unpacks the sandbox image, many small files, and on P15 the first chat waited
  minutes on disk writes. `max_concurrent_activities` defaults to 20 instead of
  5. Docker gets the hosted runners' `daemon.json` (overlay2, logs capped at 3
  files of 10 MB, live-restore), and accelerated networking is on.
  `compositions/azure` passes `runner_os_disk_size_gb` and
  `runner_max_concurrent_activities` through.
- Compositions ship without `backend.tf`. The caller generates it (Terragrunt
  `remote_state` with `generate`), so one `compositions/app` serves both clouds.
- `required_version` of the compositions is `>= 1.7`; `azurerm` is `~> 4.50`.

### Removed
- `compositions/azure-byoc` and `compositions/azure-byoc-connect` (replaced by
  `compositions/azure`), with `examples/azure-byoc` and
  `examples/azure-byoc-connect` (replaced by `examples/azure`).
- The v1 Azure output contract (`cluster_name`, `postgres_host`,
  `object_store`, `secret_store_uri`, `registry`, `runner_identity`,
  `blob_endpoint`, `eso_*`, `kube_host` and the rest). The chart reads
  `autoheal_values`.

### Fixed
- `modules/azure/runner-vmss`: the cloud-init step that writes the host's docker
  group ID into the runner unit was parsed as a YAML mapping (because of
  `cut -d: -f3`) and skipped, so `docker run --group-add __DOCKER_GID__`
  failed. The step is now a quoted string.
- `modules/azure/blob`: a `/32` entry in `allowed_ip_ranges` is written to the
  storage firewall as the bare address. Azure Storage rejects `/31` and `/32`,
  so `deployer_ip_ranges = ["203.0.113.10/32"]` failed the plan before. A `/31`
  entry now fails the module's input check with a plain message.
- `modules/azure/aks`: the system node pool declares `upgrade_settings` with a
  10% max surge, which AKS sets on a new pool. Without it, every plan after the
  first apply tried to remove the block. A cluster that has another max surge
  moves to 10% on its next apply.
- `modules/azure/vnet`: the Postgres subnet ignores `service_endpoints`. Azure
  Database for PostgreSQL adds a `Microsoft.Storage` endpoint to its delegated
  subnet when the server is created, and every later plan tried to remove it.
- `compositions/azure`: the runner scale set uses `upgrade_mode = "Manual"`.
  With `Automatic` and the `latest` image, any runner change (a new image tag,
  a new setting) made the provider start a rolling OS upgrade. That needs a
  health probe the scale set does not have, so the apply failed with
  `MaxUnhealthyInstancePercentExceededBeforeRollingUpgrade`. With `Manual` the
  provider updates and reimages each instance in the same apply. Changing the
  mode replaces the scale set once; the runners are stateless.
- `modules/azure/runner-vmss`: runner-go can pull the sandbox image from the
  ACR. The login file it reads was a copy of the host's docker login, which
  keeps the ACR token in `identitytoken` and leaves the password in `auth`
  empty. runner-go reads only `auth`, so ACR answered `authentication required`
  and no sandbox started on a new VM. `acr-login.sh` now writes the token as
  the password of the user `00000000-0000-0000-0000-000000000000`.
- `modules/azure/runner-vmss`: the runner container runs with the VM's host
  name. runner-go names its per-host task queue after the host name when there
  is no EC2 instance id, and the container's default host name is its id, so
  each runner restart or reboot moved the queue and left running sandboxes with
  no worker. `HOSTNAME` is set to the container name, which runner-go uses to
  find its own container and check its mounts at start.

### Upgrading from 1.x
`compositions/azure/moved.tf` moves the state of both v1 compositions. Point the
folder's `source` at `compositions/azure`, set the inputs below, and read the
plan before applying: it must not replace the cluster, the Postgres server, the
storage account or the vault.

- New required inputs: `hostname`, `autoheal_version`.
- From `azure-byoc`:
  - `address_space = ["10.60.0.0/16"]` becomes `network_cidr = "10.60.0.0/16"`.
  - `node_vm_size`, `node_min_count`, `node_max_count` and `postgres_sku_name`
    become `aks_node_size`, `aks_node_count`, `aks_node_max_count` and
    `postgres_sku`.
  - `federated_service_accounts` becomes `service_accounts`.
  - Set `storage_container_name = "attachments"`; the new default `autoheal`
    would replace the container.
  - Set `create_registry = true` to keep the registry. 2.0 creates none by
    default; the images come from the public registry.
  - Redis was in-cluster in 1.x. 2.0 creates Azure Managed Redis unless
    `redis_enabled = false`.
  - The cluster gets Entra integration with Azure RBAC and the Key Vault CSI
    driver add-on, in place. The deployer then needs a Kubernetes role; 2.0
    grants itself Azure Kubernetes Service RBAC Cluster Admin.
  - Destroy the separate v1 runner apply (`modules/azure/runner-vmss`) after the
    upgrade; the composition now runs the runner.
  - The plan adds an NSG on the AKS subnet. Ports 7233 and 8083 on the Temporal
    address then answer only the runner subnet.
  - The plan adds the runtime vault, its private endpoint and the api-server
    grant on it. To use a vault you already have, set
    `existing_runtime_key_vault_id`.
  - With `create_registry = true` the runner image path becomes
    `<login server>/app/runner-go`. Copy the images to `app/` and `external/` in
    the registry before the upgrade, or set `runner_image_repository`.
- From `azure-byoc-connect`: the name inputs become IDs. `aks_cluster_name`,
  `postgres_server_name`, `redis_cache_name`, `storage_account_name`,
  `key_vault_name` and `acr_name` become `existing_aks_cluster_id`,
  `existing_postgres_id`, `existing_redis_id`, `existing_storage_account_id`,
  `existing_key_vault_id` and `existing_acr_id`; `resource_group_name` becomes
  `existing_resource_group_id`. Also set `existing_network` and
  `postgres_admin_password`. `seed_secrets_enabled`, `additional_secrets` and
  `grant_app_acr_pull` are gone.
- Identities: the v1 app and External Secrets identities move to the
  api-server and secrets identities. Their names change, so both are replaced
  and get new client IDs, which reach the chart through `autoheal_values`.
- Vault entries: the v1 seeded entries are forgotten, not deleted, so a running
  1.x install keeps working until the chart upgrade. Delete them by hand
  afterwards.

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
