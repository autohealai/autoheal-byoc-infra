# One managed node group on a module-owned launch template. Nodes use the EKS
# cluster security group (no extra node security group).

locals {
  # Bottlerocket keeps the OS on a small /dev/xvda and container data on
  # /dev/xvdb; AL2023 has a single root volume on /dev/xvda.
  bottlerocket = startswith(var.node_ami_type, "BOTTLEROCKET_")

  node_volumes = local.bottlerocket ? {
    "/dev/xvda" = null
    "/dev/xvdb" = var.node_disk_size_gb
    } : {
    "/dev/xvda" = var.node_disk_size_gb
  }

  # Managed node group names are at most 63 characters and Terraform appends a
  # 26 character suffix to a name prefix.
  node_group_name_prefix = (
    length("${module.this.id}-node-") <= 37
    ? "${module.this.id}-node-"
    : "${substr(module.this.id, 0, 22)}-${substr(sha1(module.this.id), 0, 8)}-node-"
  )

  node_policy_arns = {
    worker_node   = "${local.policy_prefix}/AmazonEKSWorkerNodePolicy"
    cni           = "${local.policy_prefix}/AmazonEKS_CNI_Policy"
    ecr_read_only = "${local.policy_prefix}/AmazonEC2ContainerRegistryReadOnly"
    ssm_core      = "${local.policy_prefix}/AmazonSSMManagedInstanceCore"
  }
}

# -----------------------------------------------------------------------------
# Node IAM role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "node" {
  name = local.role_names.node

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "Ec2Assume"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  force_detach_policies = true

  tags = module.this.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.node_policy_arns

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "node_additional" {
  for_each = var.node_additional_policy_arns

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# Launch template
# -----------------------------------------------------------------------------

resource "aws_launch_template" "node" {
  name_prefix            = "${module.this.id}-node-"
  description            = "EKS managed node group ${local.cluster_name}"
  update_default_version = true

  # IMDSv2 only, and a hop limit of 1 so pods (one network hop away) cannot read
  # the node role credentials. Pods get AWS access through Pod Identity.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  dynamic "block_device_mappings" {
    for_each = local.node_volumes

    content {
      device_name = block_device_mappings.key

      ebs {
        volume_type           = "gp3"
        volume_size           = block_device_mappings.value
        iops                  = 3000
        throughput            = 125
        encrypted             = true
        kms_key_id            = var.node_disk_kms_key_arn != "" ? var.node_disk_kms_key_arn : null
        delete_on_termination = true
      }
    }
  }

  monitoring {
    enabled = true
  }

  dynamic "tag_specifications" {
    for_each = toset(["instance", "volume", "network-interface"])

    content {
      resource_type = tag_specifications.key
      tags          = merge(module.this.tags, { Name = "${module.this.id}-node" })
    }
  }

  tags = module.this.tags

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Node group
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  cluster_name           = aws_eks_cluster.this.name
  node_group_name_prefix = local.node_group_name_prefix
  node_role_arn          = aws_iam_role.node.arn
  subnet_ids             = var.subnet_ids

  # Follow the control plane version, so raising kubernetes_version upgrades the
  # nodes after the control plane.
  version = aws_eks_cluster.this.version

  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types
  labels         = var.node_labels

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable_percentage = var.node_max_unavailable_percentage
  }

  node_repair_config {
    enabled = var.node_repair_enabled
  }

  tags = module.this.tags

  lifecycle {
    # A replacement (new instance types, AMI type, capacity type or subnets)
    # brings the new group up before the old one drains.
    create_before_destroy = true

    precondition {
      condition     = var.node_min_size <= var.node_desired_size && var.node_desired_size <= var.node_max_size
      error_message = "node sizes must satisfy node_min_size <= node_desired_size <= node_max_size."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_nodes,
  ]
}
