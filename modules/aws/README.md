# AWS modules

Own-model Terraform modules for a BYOC-on-EKS Autoheal install. Each mirrors an
Azure counterpart and feeds the shared cross-cloud output contract
(see [docs/MODULE_STANDARD.md](../../docs/MODULE_STANDARD.md)). They are wired
together by [`compositions/aws-byoc`](../../compositions/aws-byoc).

| Module | Azure analogue | Role |
|--------|----------------|------|
| [`vpc`](vpc) | `azure/vnet` | VPC, public/private subnets per AZ, NAT, EKS discovery tags |
| [`eks`](eks) | `azure/aks` | EKS cluster, node group, OIDC provider, EBS CSI add-on |
| [`rds-cluster`](rds-cluster) | `azure/postgres-flexible` | Aurora PostgreSQL (provisioned) |
| [`elasticache`](elasticache) | `azure/redis` | ElastiCache Redis (node-based) |
| [`s3`](s3) | `azure/blob` | Attachments bucket |
| [`secrets-manager`](secrets-manager) | `azure/keyvault` | Connection secrets under a prefix |
| [`ecr`](ecr) | `azure/acr` | Per-service repositories under the account registry |
| [`irsa`](irsa) | `azure/workload-identity` | App IAM role federated to the cluster OIDC |
| [`runner-asg`](runner-asg) | `azure/runner-vmss` | EC2 ASG runner (separate post-install apply) |

Naming and tags follow the repo's null-label convention; `label.tf` in each module
is a copyable template forwarding to `modules/_shared/label`.
