# compositions/aws-byoc

The AWS recipe: wires the `modules/aws/*` building blocks into the full Autoheal
BYOC stack and emits the shared output contract — the same output names as
`azure-byoc`, so the Autoheal app install is cloud-agnostic.

Planned once the AWS modules land (VPC, Aurora, ElastiCache, S3, Secrets Manager,
ECR, EKS, runner ASG, IRSA).

Outputs (shared contract): `cluster_name`, `postgres_host`, `redis_endpoint`,
`object_store`, `secret_store_uri`, `registry`, `runner_identity`.
