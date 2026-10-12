# Autoheal BYOC — AWS EKS

EKS cluster + managed node group + IRSA OIDC provider for a BYOC-on-EKS Autoheal
install. This is the compute plane the app runs on. The cluster's OIDC provider is
what `modules/aws/irsa` federates app service accounts against, and the EBS CSI
add-on backs the stateful workloads' PersistentVolumes.

Trimmed to BYOC essentials versus the legacy monorepo module: no ALB controller
IAM — the ingress controller is installed at app-install time with the upstream
policy, not by this infra module.

The Azure analogue is `modules/azure/aks`. Naming and tags follow the repo's
null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

> `cluster_name` must match the value passed to `modules/aws/vpc` — the VPC tags
> subnets with `kubernetes.io/cluster/<cluster_name>=shared` for load-balancer and
> node discovery.

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     Module-specific inputs are in variables.tf; label inputs come from label.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `vpc_id` / `private_subnet_ids` / `public_subnet_ids` | network placement | (required / required / `[]`) |
| `cluster_name` | cluster name (match the VPC's) | `""` (label id) |
| `kubernetes_version` | control-plane version | `1.34` |
| `node_instance_types` / `node_desired_size` | node group sizing | `["m7g.large"]` / `3` |
| `kms_key_arn` | envelope-encrypt k8s secrets | `""` (off) |

### Key outputs

| Name | Description |
|------|-------------|
| `cluster_name` | maps to the contract `cluster_name` |
| `oidc_provider_arn` / `oidc_provider_url` | feed to `modules/aws/irsa` |
| `cluster_endpoint` / `cluster_certificate_authority_data` | kubeconfig inputs |
<!-- END_TF_DOCS -->
