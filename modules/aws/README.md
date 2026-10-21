# AWS modules

Own-model Terraform modules for a BYOC-on-EKS Autoheal install. Each mirrors an
Azure counterpart and feeds the shared cross-cloud output contract
(see [docs/MODULE_STANDARD.md](../../docs/MODULE_STANDARD.md)). They are wired
together by [`compositions/aws`](../../compositions/aws).

| Module | Azure analogue | Role |
|--------|----------------|------|
| [`vpc`](vpc) | `azure/vnet` | VPC over 2 to 6 zones: public, private, data and runner subnets, NAT, flow logs, interface and gateway endpoints |
| [`eks`](eks) | `azure/aks` | EKS cluster, managed node group, access entries and managed add-ons (Pod Identity Agent, Secrets Store CSI with the AWS provider, EBS CSI) |
| [`aurora-postgres`](aurora-postgres) | `azure/postgres-flexible` | Aurora PostgreSQL, provisioned or Serverless v2, CMK, TLS only |
| [`elasticache`](elasticache) | `azure/managed-redis` | ElastiCache replication group, cluster mode disabled, TLS and AUTH |
| [`s3`](s3) | `azure/blob` | One bucket: attachments, artifacts or the tenant Git Registry |
| [`kms`](kms) | (Key Vault keys) | One customer managed key with rotation and a key policy |
| [`secrets-manager`](secrets-manager) | `azure/keyvault` | Install secrets under a name prefix, encrypted with a CMK |
| [`pod-identity`](pod-identity) | `azure/workload-identity` | IAM role bound to service accounts through EKS Pod Identity |
| [`nlb`](nlb) | (internal load balancer IPs) | NLB with TCP listeners and ip target groups for TargetGroupBinding |
| [`route53`](route53) | `azure/dns` | Records in a hosted zone the customer already has |
| [`ecr`](ecr) | `azure/acr` | Pull-through cache of the public Autoheal registry |
| [`runner-asg`](runner-asg) | `azure/runner-vmss` | EC2 Auto Scaling group that runs runner-go |

Naming and tags follow the repo's null-label convention; `label.tf` in each module
is a copyable template forwarding to `modules/_shared/label`.
