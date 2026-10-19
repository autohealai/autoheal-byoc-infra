# examples/aws

A starting point for your own deployment repository on AWS. Copy this folder
into a repository you own, edit the values, and run it from your pipeline.

```text
root.hcl                     state backend, shared by every folder
prod/
  versions.hcl               the infra tag and the chart version for prod
  infra/terragrunt.hcl       cloud resources (compositions/aws)
  app/terragrunt.hcl         the chart (compositions/app)
  app/values-customer.yaml   your chart settings
```

Each folder has its own state file (`autoheal/prod/infra`, `autoheal/prod/app`).
For a second environment, copy `prod/` to `staging/` and change the inputs.

## Which resources you bring

`prod/infra/terragrunt.hcl` creates everything apart from the hosted zone. Each
building block takes an `existing_*` ID; uncomment the ones you already have.

| You bring | Set |
|-----------|-----|
| Nothing (we create the VPC, EKS, Aurora, ElastiCache, S3, KMS keys) | `network_cidr` |
| Your network | `existing_network` (VPC and subnet IDs). The nodes' security group must allow the NLBs on the target ports; see the chart's `docs/prerequisites.md`. |
| Your cluster, database, cache, buckets, key or registry | `existing_eks_cluster_arn`, `existing_postgres_arn`, `existing_redis_arn`, `existing_attachments_bucket_arn`, `existing_artifacts_bucket_arn`, `existing_kms_key_arn`, `existing_registry_url` |
| Pod Identity associations made by your administrators | `create_pod_identity_associations = false`, then run the commands in the `required_role_assignments` output |
| DNS outside Route 53 | `create_dns_records = false`, then create the records in the `required_dns_records` output |

A brought resource is only read. Mixes that cannot work (a brought cluster
without its network, a database older than PostgreSQL 15, ElastiCache in cluster
mode, a bucket in another region) stop the plan with a message saying what to
change.

A brought EKS cluster needs the `eks-pod-identity-agent` add-on, the Secrets
Store CSI driver with the AWS provider (`aws-secrets-store-csi-driver-provider`
add-on) and an AWS Load Balancer Controller. Without a controller of its own,
keep `aws_load_balancer_controller = { enabled = true }` in
`prod/app/terragrunt.hcl` and leave `create_load_balancer_controller_role` on in
the infra folder.

## Before the first run

1. Tools on the pipeline runner: Terraform or OpenTofu 1.10 or later (for S3
   state locking with `use_lockfile`), Terragrunt, and the `aws` CLI.
2. Permissions for the identity that runs Terraform: AdministratorAccess, or
   PowerUserAccess plus the IAM rights to create roles, policies and instance
   profiles. When your account requires a permissions boundary on new roles,
   set `iam_permissions_boundary_arn`. That identity becomes a cluster admin of
   the EKS cluster we create; add others with `cluster_admin_principal_arns`.
3. Edit the names in `root.hcl`, then create the state bucket once:

   ```bash
   ./scripts/bootstrap-state-aws.sh \
     --bucket acme-autoheal-tfstate \
     --region us-west-2
   ```

   The script is in autoheal-byoc-infra. It turns on versioning, default
   encryption and TLS-only access, and blocks public access. Give the pipeline
   identity read and write access to the bucket.
4. Edit `prod/infra/terragrunt.hcl` and `prod/app/values-customer.yaml`.

## Secrets

No secret goes in these files. Pass them to the infra folder as environment
variables from your pipeline's secret store; Terraform writes them to Secrets
Manager under `secrets_name_prefix` (`acme-prod-autoheal/` here), encrypted with
the secrets KMS key:

| Variable | Secret | When |
|----------|--------|------|
| `TF_VAR_llm_api_key` | `llm-api-key` | When your LLM provider uses an API key and the chart's LLM gateway is off. Not with Bedrock, which uses the agents' Pod Identity roles. |
| `TF_VAR_postgres_admin_password` | `postgres-admin-password` | Only with `existing_postgres_arn`; for a database we create, Terraform generates it |
| `TF_VAR_redis_auth_token` | `redis-access-key` | Only with an `existing_redis_arn` that has AUTH on |
| `TF_VAR_sso_client_secret` | `sso-client-secret` | When SSO is on |
| `TF_VAR_tls_certificate` | `tls-certificate`, `tls-private-key` | When the edge serves your own certificate; an HCL object `{ certificate = "<PEM chain>", private_key = "<PEM>" }` |
| `TF_VAR_github_app_private_key` | `github-app-private-key` | When you connect a GitHub App; the PEM, which Terraform stores base64-encoded |
| `TF_VAR_github_app_webhook_secret` | `github-app-webhook-secret` | When you connect a GitHub App |
| `TF_VAR_llm_gateway_api_key` | `gateway-api-key` | When the chart's LLM gateway is on, with any kind except `custom`. For a gateway that ignores it, such as Portkey OSS, any value. |
| `TF_VAR_llm_gateway_extra_headers` | `gateway-extra-headers` | When the gateway needs extra headers; a JSON object of strings, for example `{"x-portkey-config":"<config JSON>"}` |

Terraform generates and stores the rest (database passwords, the Redis AUTH
token, the JWT key, the Zitadel master key, the first admin password, the OAuth
keys and the tool response server secret).

Tenant secrets that Autoheal writes at run time go under
`runtime_secrets_name_prefix` (`acme-prod-autoheal-runtime/` here), which only
api-server-go may manage.

## Running it

```bash
cd prod/infra && terragrunt plan && terragrunt apply
cd ../app     && terragrunt plan && terragrunt apply
```

The app folder reads `autoheal_values` and `cluster` from the infra folder's
state. Before the infra folder has been applied, its plan uses the placeholder
outputs in the `dependency` block. The app folder logs in to EKS with
`aws eks get-token`, so the pipeline's AWS identity must be a cluster admin.
It installs the AWS Load Balancer Controller first, then the chart.

## Upgrading

Change the two numbers in `prod/versions.hcl` (after staging has run them), then
run both folders again. Read the release notes in autoheal-byoc-infra's
`CHANGELOG.md` first.

## Installing with Helm or Flux instead

Run only the infra folder, install the AWS Load Balancer Controller (or use the
cluster's own), then write the infra values to a file and install the chart
with them:

```bash
cd prod/infra && terragrunt output -raw autoheal_values_yaml > values-infra.yaml
helm upgrade --install autoheal oci://public.ecr.aws/e4h3h0d9/charts/autoheal \
  --version 1.0.0 -n autoheal --create-namespace \
  -f values-infra.yaml -f ../app/values-customer.yaml --atomic --wait --timeout 20m
```

`values-infra.yaml` holds names, addresses and target group ARNs, never a secret.
