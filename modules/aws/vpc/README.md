# Autoheal BYOC — AWS VPC

VPC network substrate for a BYOC-on-EKS Autoheal install: public + private subnets
(one pair per AZ), an Internet Gateway, one NAT gateway per AZ for private egress,
and the EKS subnet discovery tags (`kubernetes.io/role/{elb,internal-elb}` and the
per-cluster shared tag) so the load-balancer controllers work.

The Azure analogue is `modules/azure/vnet`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     Module-specific inputs are in variables.tf; label inputs come from label.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `vpc_cidr` | VPC CIDR | `10.60.0.0/16` |
| `availability_zones` | AZs to spread subnets across | — |
| `cluster_name` | EKS cluster name for subnet discovery tags | — |

### Key outputs

| Name | Description |
|------|-------------|
| `vpc_id` | VPC id |
| `private_subnet_ids` | private subnets (EKS/RDS/ElastiCache/runner) |
| `public_subnet_ids` | public subnets (NAT, public LBs) |
| `nat_public_ips` | per-AZ NAT egress IPs |
<!-- END_TF_DOCS -->
