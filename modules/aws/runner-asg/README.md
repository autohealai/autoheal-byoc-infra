# Autoheal BYOC — AWS runner ASG

EC2 Auto Scaling Group runner — the EKS analogue of the AKS VMSS runner. Each
instance runs the runner-go worker as a container (Docker-out-of-Docker: it drives
the host Docker daemon via the mounted socket to launch sandbox containers) and
polls Temporal on the `runners` namespace via the internal NLB.

This is a **separate unit** from the main `aws-byoc` composition on purpose: it
needs `temporal_host` (the internal NLB endpoint), which only exists after the
cluster and Temporal are deployed. Apply it after the app install, feeding forward
the discovered endpoint — mirroring `modules/azure/runner-vmss`.

Identity is an instance profile granted `AmazonEC2ContainerRegistryReadOnly` (pulls
via the `amazon-ecr-credential-helper`, no static registry creds) and
`AmazonSSMManagedInstanceCore` (break-glass via SSM Session Manager, no SSH key or
inbound port). It does not read Secrets Manager — in-cluster apps do, via IRSA.

The Azure analogue is `modules/azure/runner-vmss`. Naming and tags follow the
repo's null-label convention (see `label.tf` and
[docs/MODULE_STANDARD.md](../../../docs/MODULE_STANDARD.md)).

## Usage

See [examples/basic](examples/basic) for a runnable configuration.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs populates the providers / inputs / outputs tables here.
     Module-specific inputs are in variables.tf; label inputs come from label.tf. -->

### Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `vpc_id` / `subnet_ids` | network placement (private subnets) | (required) |
| `temporal_host` | internal NLB endpoint `host:port` | (required) |
| `ecr_registry` / `runner_image` / `sandbox_image` | images | (required) |
| `instance_type` | Graviton by default | `m7g.xlarge` |
| `root_volume_size_gb` | large for Docker layers + caches | `200` |

### Key outputs

| Name | Description |
|------|-------------|
| `asg_name` | runner Auto Scaling Group name |
| `role_arn` | runner instance-profile role ARN |
<!-- END_TF_DOCS -->
