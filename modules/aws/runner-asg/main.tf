# EC2 Auto Scaling Group runner — the EKS analogue of the AKS VMSS runner. Each
# instance runs the runner-go worker as a container (Docker-out-of-Docker: it drives
# the host Docker daemon via the mounted socket to launch sandbox containers),
# polling Temporal on the `runners` namespace via the internal NLB.
#
# This is a SEPARATE unit from the main composition on purpose: it needs
# temporal_host (the internal NLB endpoint), which only exists after the cluster +
# Temporal are deployed (discover-and-feed-forward). The runner subnets + their NAT
# egress live in modules/aws/vpc (private subnets).
#
# Identity: an instance profile granted AmazonEC2ContainerRegistryReadOnly (image
# pulls via the amazon-ecr-credential-helper, no static registry creds) and
# AmazonSSMManagedInstanceCore (break-glass access via SSM Session Manager, no SSH
# key or inbound port). It does NOT read Secrets Manager; in-cluster apps do, via
# IRSA. Naming/tags come from the null-label base (module.this); see label.tf.

data "aws_ssm_parameter" "al2023_arm64" {
  count = var.ami_id == "" ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ssm_parameter.al2023_arm64[0].value
}

resource "aws_iam_role" "runner" {
  name = "${module.this.id}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = module.this.tags
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.runner.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.runner.name
}

resource "aws_iam_instance_profile" "runner" {
  name = "${module.this.id}-profile"
  role = aws_iam_role.runner.name
  tags = module.this.tags
}

# Egress-only: the worker reaches Temporal (internal NLB) and pulls images via the
# subnet NAT gateway. No inbound; access is via SSM Session Manager.
resource "aws_security_group" "runner" {
  name        = "${module.this.id}-sg"
  description = "Autoheal runner-go worker (egress only; access via SSM)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(module.this.tags, { Name = "${module.this.id}-sg" })
}

resource "aws_launch_template" "runner" {
  name_prefix   = "${module.this.id}-"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  iam_instance_profile {
    arn = aws_iam_instance_profile.runner.arn
  }

  vpc_security_group_ids = [aws_security_group.runner.id]

  user_data = base64encode(templatefile("${path.module}/cloudinit.yaml.tftpl", {
    temporal_host             = var.temporal_host
    runner_image              = var.runner_image
    sandbox_image             = var.sandbox_image
    ecr_registry              = var.ecr_registry
    runner_name               = var.runner_name
    max_concurrent_activities = var.max_concurrent_activities
  }))

  # IMDSv2 required.
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(module.this.tags, { Name = module.this.id })
  }

  tags = module.this.tags
}

resource "aws_autoscaling_group" "runner" {
  name                = module.this.id
  vpc_zone_identifier = var.subnet_ids
  desired_capacity    = var.instance_count
  min_size            = var.min_size
  max_size            = var.max_size

  launch_template {
    id      = aws_launch_template.runner.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(module.this.tags, { Name = module.this.id })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
