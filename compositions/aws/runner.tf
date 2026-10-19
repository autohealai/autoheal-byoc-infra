# Runner VMs: runner-go on an Auto Scaling group in the runner subnets, created
# in this apply. They connect to Temporal through the runner load balancer on
# 7233 and post sandbox tool results to the api-server-go internal listener on
# 8083 of the same load balancer. Until the chart is installed the runner keeps
# retrying.
#
# The instances have no SSH key and no inbound rule; use SSM Session Manager.
# IMDSv2 with a hop limit of 1 keeps the sandbox containers away from the
# instance role. A change to the launch template (image, settings) starts an
# instance refresh.
#
# The image is <registry>/app/runner-go:chart-<autoheal_version>, the layout the
# chart uses for its own images. The registry is the ECR pull-through cache or
# the customer's mirror when there is one, else the public registry.
# runner_image_repository and runner_image_tag override it. When the image is in
# ECR the VMs pull with the instance role through the ECR credential helper.

module "runner" {
  source = "../../modules/aws/runner-asg"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = ["runner"]
  tags        = var.tags

  vpc_id     = local.vpc_id
  subnet_ids = local.runner_subnet_ids

  instance_type       = var.runner_instance_type
  architecture        = var.runner_architecture
  instance_count      = var.runner_node_count
  root_volume_size_gb = var.runner_root_volume_size_gb

  temporal_host              = "${local.runner_nlb_dns_name}:7233"
  tool_response_callback_url = "http://${local.runner_nlb_dns_name}:8083/api/v1/internal/sandbox-tool-responses"
  runner_image               = local.runner_image
  sandbox_image              = var.runner_sandbox_image
  runner_name                = "${local.id}-runner"
  max_concurrent_activities  = var.runner_max_concurrent_activities

  ecr_registry_host        = local.runner_ecr_host
  permissions_boundary_arn = var.iam_permissions_boundary_arn

  additional_iam_policy_arns = merge(
    { for k, v in { "ecr-read" = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" } : k => v if local.runner_ecr_host != "" },
    { for k, v in { "ecr-pull-through" = one(aws_iam_policy.ecr_pull_through[*].arn) } : k => v if local.create_registry },
  )
}

locals {
  runner_image_repository = var.runner_image_repository != "" ? var.runner_image_repository : (
    local.image_registry != "" ? "${local.image_registry}/app/runner-go" : "public.ecr.aws/e4h3h0d9/app/runner-go"
  )
  runner_image = "${local.runner_image_repository}:${var.runner_image_tag != "" ? var.runner_image_tag : "chart-${var.autoheal_version}"}"

  # The ECR host of the runner image, or "" when it is not in a private ECR
  # registry.
  runner_ecr_host = try(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com(?:\\.cn)?", lower(local.runner_image_repository)), "")
}
