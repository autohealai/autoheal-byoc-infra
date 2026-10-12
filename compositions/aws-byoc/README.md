# Autoheal BYOC — AWS composition (`aws-byoc`)

Full AWS BYOC stack. Wires the `modules/aws/*` building blocks into one install and
emits the cross-cloud output contract shared with `compositions/azure-byoc`, so the
Autoheal app install is cloud-agnostic.

This is the **create** composition (Autoheal provisions the infrastructure). The
Azure twin is `compositions/azure-byoc`; a connect-mode AWS twin (customer provisions
infra, Autoheal only connects the app) can follow `compositions/azure-byoc-connect`.

## What it creates

| Module | Resource |
|--------|----------|
| `vpc` | VPC, public/private subnets per AZ, NAT gateways, EKS discovery tags |
| `eks` | EKS cluster, managed node group, OIDC provider, EBS CSI add-on |
| `rds-cluster` | Aurora PostgreSQL (provisioned writer + optional reader) |
| `elasticache` | ElastiCache Redis replication group (node-based) |
| `s3` | Attachments bucket |
| `ecr` | Per-service repositories under the account registry |
| `secrets-manager` | PostgreSQL + Redis connection secrets under a prefix |
| `irsa` | App IAM role federated to the cluster OIDC provider |

## Deliberately NOT here

- **The runner ASG.** It needs `temporal_host` (the internal NLB endpoint), which
  only exists after the app + Temporal are deployed. Apply `modules/aws/runner-asg`
  separately after the app install, feeding forward the discovered endpoint and this
  composition's `vpc_id` / `private_subnet_ids`. This mirrors the Azure runner unit.

## Output contract

`cluster_name`, `postgres_host`, `redis_endpoint`, `object_store`,
`secret_store_uri`, `registry`, `runner_identity` — identical names to
`azure-byoc`. Plus extras for later steps: `vpc_id`, `private_subnet_ids`,
`oidc_provider_arn`, `oidc_provider_url`, `cluster_endpoint`,
`cluster_certificate_authority_data`.

## Usage

Drive it through the Terragrunt wrapper in [`examples/aws-byoc`](../../examples/aws-byoc),
which supplies the S3 remote-state backend and the install's inputs. State never
lives on a laptop for a real install.
