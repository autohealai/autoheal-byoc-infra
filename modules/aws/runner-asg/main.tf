# EC2 Auto Scaling group runner, the EKS analogue of modules/azure/runner-vmss.
# Each instance runs the runner-go worker as a container (Docker-out-of-Docker:
# it drives the host Docker daemon through the mounted socket to launch sandbox
# containers), polling Temporal on the `runners` namespace through the internal
# NLB.
#
# The composition creates the runner in the same apply as the cluster, so
# temporal_host (the NLB DNS name) exists before Temporal answers on it.
# runner-go runs under systemd with Restart=always and retries until Temporal
# answers. Before each start the unit pulls the image and keeps retrying with a
# backoff until the pull succeeds. cloud-init (cloudinit.yaml.tftpl) is the
# Azure template with only the AWS changes: the Amazon Linux docker package,
# and an ECR login through the instance role instead of an ACR login.
#
# The launch template requires IMDSv2 with a hop limit of 1, so containers
# (including untrusted sandboxes) cannot reach the instance role. runner-go then
# falls back to the host name for its per-host task queue, and resource-name
# host names make that the instance ID. There is no SSH key and no ingress
# rule; access is through SSM Session Manager. Any change to the launch
# template (a new runner image, a new AMI) rolls the instances through an
# instance refresh.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

data "aws_partition" "current" {}

data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == "" ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ssm_parameter.al2023[0].insecure_value

  # IAM names are limited to 64 characters. A long label id is cut and given
  # a short hash so two long ids still get different names.
  role_name_full    = "${module.this.id}-role"
  role_name         = length(local.role_name_full) <= 64 ? local.role_name_full : "${substr(local.role_name_full, 0, 57)}-${substr(md5(local.role_name_full), 0, 6)}"
  profile_name_full = "${module.this.id}-profile"
  profile_name      = length(local.profile_name_full) <= 64 ? local.profile_name_full : "${substr(local.profile_name_full, 0, 57)}-${substr(md5(local.profile_name_full), 0, 6)}"

  user_data = templatefile("${path.module}/cloudinit.yaml.tftpl", {
    temporal_host              = var.temporal_host
    tool_response_callback_url = var.tool_response_callback_url
    runner_image               = var.runner_image
    sandbox_image              = var.sandbox_image
    runner_name                = var.runner_name
    max_concurrent_activities  = var.max_concurrent_activities
    ecr_registry_host          = var.ecr_registry_host
  })
}

# Looked up for the root device name, which differs between AMI families, and
# to check the architecture before anything launches.
data "aws_ami" "this" {
  include_deprecated = true

  filter {
    name   = "image-id"
    values = [local.ami_id]
  }
}

data "aws_ec2_instance_type" "this" {
  instance_type = var.instance_type
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  description          = "Autoheal runner instances ${module.this.id}."
  permissions_boundary = var.permissions_boundary_arn == "" ? null : var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.${data.aws_partition.current.dns_suffix}" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = module.this.tags
}

# SSM Session Manager is the only way in: no SSH key, no ingress rule.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = var.additional_iam_policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  name = local.profile_name
  role = aws_iam_role.this.name
  tags = module.this.tags
}

resource "aws_security_group" "this" {
  name        = "${module.this.id}-sg"
  description = "Autoheal runner instances (egress only, access through SSM)"
  vpc_id      = var.vpc_id

  tags = merge(module.this.tags, { Name = "${module.this.id}-sg" })
}

# Sandboxes reach the internet (git hosts, package registries, customer
# APIs), and the runner reaches Temporal, ECR and SSM. Keyed by list position
# so the CIDRs may come from the same apply.
#trivy:ignore:AVD-AWS-0104 Sandboxes need internet egress; egress_cidr_blocks narrows it and there is no ingress rule.
resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = { for i in range(length(var.egress_cidr_blocks)) : tostring(i) => i }

  security_group_id = aws_security_group.this.id
  description       = "All egress"
  ip_protocol       = "-1"
  cidr_ipv4         = var.egress_cidr_blocks[each.value]

  tags = module.this.tags
}

resource "aws_launch_template" "this" {
  name                   = module.this.id
  description            = "Autoheal runner-go ${var.runner_name}"
  image_id               = local.ami_id
  instance_type          = var.instance_type
  update_default_version = true
  user_data              = base64encode(local.user_data)

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  # No public address: egress goes through the subnets' NAT gateway.
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = concat([aws_security_group.this.id], var.additional_security_group_ids)
  }

  # IMDSv2 only, and a hop limit of 1 so the instance role is out of reach of
  # containers on the Docker bridge network.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  # The host name is the instance ID (i-0123456789abcdef0.<region>.compute.internal).
  # runner-go uses it for its per-host task queue.
  private_dns_name_options {
    hostname_type                     = "resource-name"
    enable_resource_name_dns_a_record = true
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = data.aws_ami.this.root_device_name

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size_gb
      iops                  = var.root_volume_iops
      throughput            = var.root_volume_throughput
      encrypted             = true
      kms_key_id            = var.root_volume_kms_key_arn == "" ? null : var.root_volume_kms_key_arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(module.this.tags, { Name = module.this.id })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(module.this.tags, { Name = module.this.id })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(module.this.tags, { Name = module.this.id })
  }

  tags = module.this.tags

  lifecycle {
    precondition {
      condition     = data.aws_ami.this.architecture == var.architecture
      error_message = "The AMI architecture does not match var.architecture."
    }

    precondition {
      condition     = contains(data.aws_ec2_instance_type.this.supported_architectures, var.architecture)
      error_message = "instance_type does not support var.architecture (for example m7g is arm64, m7i is x86_64)."
    }

    precondition {
      condition     = length(local.user_data) <= 16384
      error_message = "The rendered cloud-init is larger than the 16 KB EC2 user data limit."
    }
  }
}

resource "aws_autoscaling_group" "this" {
  name                = module.this.id
  vpc_zone_identifier = var.subnet_ids
  min_size            = var.instance_count
  max_size            = var.instance_count
  desired_capacity    = var.instance_count

  health_check_type         = "EC2"
  health_check_grace_period = 300
  default_instance_warmup   = 300

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  # latest_version, not $Latest: only a version change starts an instance
  # refresh.
  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  # Replaces the instances when the launch template changes. In-flight
  # sandboxes on a replaced instance are lost; Temporal retries the
  # activities on the other runners.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = var.instance_refresh_min_healthy_percentage
      max_healthy_percentage = var.instance_refresh_max_healthy_percentage
      skip_matching          = true
    }
  }

  # The launch template tags the instances and their volumes.
  dynamic "tag" {
    for_each = merge(module.this.tags, { Name = module.this.id })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_iam_role_policy_attachment.additional,
  ]

  lifecycle {
    precondition {
      condition     = var.instance_refresh_max_healthy_percentage - var.instance_refresh_min_healthy_percentage <= 100
      error_message = "instance_refresh_max_healthy_percentage may be at most 100 above instance_refresh_min_healthy_percentage."
    }
  }
}
