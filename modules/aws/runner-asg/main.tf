# EC2 Auto Scaling group runner, the AWS analogue of modules/azure/runner-vmss.
# Each instance runs the runner-go worker as a container (Docker-out-of-Docker:
# it drives the host Docker daemon through the mounted socket to launch sandbox
# containers), polling Temporal on the `runners` namespace.
#
# compositions/aws-runner creates the runner as its own step, after the app.
# temporal_host is the internal runner load balancer of compositions/aws on
# 7233, which the runner dials as Autoheal's hosted runners do: plain gRPC, no
# key, and only the network decides who reaches it. runner-go runs under
# systemd with Restart=always and retries until Temporal answers. Before each
# start the unit sets up the container firewall and pulls the image, the pull
# retried with a backoff until it succeeds. cloud-init (cloudinit.yaml.tftpl)
# is the Azure template with the AWS changes: the Amazon Linux packages, an ECR
# login through the instance role instead of an ACR login, and no key.
# trusted_ca_certificates go into the system trust store, for a registry or a
# proxy with a private CA. custom_ca_certificate goes to runner-go, which adds
# it to every sandbox it creates.
#
# The launch template requires IMDSv2 with a hop limit of 1. runner-go runs on
# a Docker network of its own, and container-firewall.sh rejects container
# traffic to the metadata address, and sandbox traffic to the runner load
# balancer and sandbox_blocked_destinations. So sandboxes, which run untrusted
# code, can reach neither the instance role nor Temporal. runner-go then falls
# back to the host name for its per-host task queue, and resource-name host
# names make that the instance ID. Access is through SSM Session Manager by
# default, or SSH with key_name. Any change to the launch template (a new
# runner image, a new AMI) rolls the instances through an instance refresh.
#
# A central team may own IAM or the security group: existing_instance_profile_arn
# and existing_security_group_id replace the module's own, and
# required_role_policies lists what the brought role needs. Naming and tags come
# from the null-label base (module.this); see label.tf.

data "aws_partition" "current" {}

data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == "" && var.ami_name_filter == "" ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

data "aws_ami" "by_name" {
  count = var.ami_id == "" && var.ami_name_filter != "" ? 1 : 0

  most_recent = true
  owners      = var.ami_owners

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "architecture"
    values = [var.architecture]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  lifecycle {
    precondition {
      condition     = length(var.ami_owners) > 0
      error_message = "ami_name_filter needs ami_owners, the accounts that publish the image."
    }
  }
}

locals {
  ami_id = (
    var.ami_id != "" ? var.ami_id :
    var.ami_name_filter != "" ? data.aws_ami.by_name[0].id :
    data.aws_ssm_parameter.al2023[0].insecure_value
  )

  create_role           = var.existing_instance_profile_arn == ""
  create_security_group = var.existing_security_group_id == ""
  security_group_id     = local.create_security_group ? aws_security_group.this[0].id : var.existing_security_group_id

  # IAM names are limited to 64 characters. A long label id is cut and given
  # a short hash so two long ids still get different names.
  role_name_full    = "${module.this.id}-role"
  role_name         = length(local.role_name_full) <= 64 ? local.role_name_full : "${substr(local.role_name_full, 0, 57)}-${substr(md5(local.role_name_full), 0, 6)}"
  profile_name_full = "${module.this.id}-profile"
  profile_name      = length(local.profile_name_full) <= 64 ? local.profile_name_full : "${substr(local.profile_name_full, 0, 57)}-${substr(md5(local.profile_name_full), 0, 6)}"

  ec2_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.${data.aws_partition.current.dns_suffix}" }
      Action    = "sts:AssumeRole"
    }]
  })

  # Pull from ecr_registry_host, limited to ecr_repository_prefix when set. The
  # same actions as the pull_policy_json of modules/aws/ecr: a pull-through
  # cache creates and imports a repository on its first pull.
  ecr = var.ecr_registry_host == "" ? null : regex("^([0-9]{12})\\.dkr\\.ecr(?:-fips)?\\.([a-z0-9-]+)\\.", var.ecr_registry_host)
  ecr_pull_policy = local.ecr == null ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PullImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:BatchImportUpstreamImage",
          "ecr:CreateRepository",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ecr:${local.ecr[1]}:${local.ecr[0]}:repository/${var.ecr_repository_prefix == "" ? "" : "${var.ecr_repository_prefix}/"}*"
      },
    ]
  })

  inline_policies = merge(
    local.ecr_pull_policy == null ? {} : { ecr-pull = local.ecr_pull_policy },
    var.additional_inline_policies,
  )

  ssm_policy_arn      = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  managed_policy_arns = merge(var.ssm_enabled ? { ssm = local.ssm_policy_arn } : {}, var.additional_iam_policy_arns)

  # The runner reaches Temporal and the tool result listener directly; the
  # metadata address and loopback never go through a proxy.
  temporal_hostname  = split(":", var.temporal_host)[0]
  tool_response_host = var.tool_response_callback_url == "" ? "" : regex("^https?://([^/:]+)", var.tool_response_callback_url)[0]
  no_proxy = join(",", distinct(compact(concat(
    ["localhost", "127.0.0.1", "169.254.169.254", local.temporal_hostname, local.tool_response_host],
    var.no_proxy,
  ))))

  # What sandboxes may not reach: the runner load balancer, which takes no key,
  # and any more destinations given.
  sandbox_blocked_destinations = distinct(compact(concat(
    [local.temporal_hostname, local.tool_response_host],
    var.sandbox_blocked_destinations,
  )))

  user_data = templatefile("${path.module}/cloudinit.yaml.tftpl", {
    temporal_host                = var.temporal_host
    tool_response_callback_url   = var.tool_response_callback_url
    sandbox_blocked_destinations = local.sandbox_blocked_destinations
    runner_image                 = var.runner_image
    sandbox_image                = var.sandbox_image
    runner_name                  = var.runner_name
    max_concurrent_activities    = var.max_concurrent_activities
    ecr_registry_host            = var.ecr_registry_host
    http_proxy                   = var.http_proxy
    no_proxy                     = local.no_proxy
    trusted_ca_certificates      = var.trusted_ca_certificates
    custom_ca_certificate        = var.custom_ca_certificate
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
  count = local.create_role ? 1 : 0

  name                 = local.role_name
  description          = "Autoheal runner instances ${module.this.id}."
  permissions_boundary = var.permissions_boundary_arn == "" ? null : var.permissions_boundary_arn
  assume_role_policy   = local.ec2_trust_policy

  tags = module.this.tags
}

resource "aws_iam_role_policy" "this" {
  for_each = local.create_role ? local.inline_policies : {}

  name   = each.key
  role   = aws_iam_role.this[0].name
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.create_role ? local.managed_policy_arns : {}

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  count = local.create_role ? 1 : 0

  name = local.profile_name
  role = aws_iam_role.this[0].name
  tags = module.this.tags
}

resource "aws_security_group" "this" {
  count = local.create_security_group ? 1 : 0

  name        = "${module.this.id}-sg"
  description = "Autoheal runner instances"
  vpc_id      = var.vpc_id

  tags = merge(module.this.tags, { Name = "${module.this.id}-sg" })
}

# Sandboxes reach the internet (git hosts, package registries, customer
# APIs), and the runner reaches Temporal and the registry.
# Keyed by list position so the CIDRs may come from the same apply.
#trivy:ignore:AVD-AWS-0104 Sandboxes need internet egress; egress_cidr_blocks narrows it.
resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.create_security_group ? { for i in range(length(var.egress_cidr_blocks)) : tostring(i) => i } : {}

  security_group_id = aws_security_group.this[0].id
  description       = "All egress"
  ip_protocol       = "-1"
  cidr_ipv4         = var.egress_cidr_blocks[each.value]

  tags = module.this.tags
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = local.create_security_group ? { for i in range(length(var.ssh_ingress_cidr_blocks)) : tostring(i) => i } : {}

  security_group_id = aws_security_group.this[0].id
  description       = "SSH"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.ssh_ingress_cidr_blocks[each.value]

  tags = module.this.tags
}

resource "aws_launch_template" "this" {
  name                   = module.this.id
  description            = "Autoheal runner-go ${var.runner_name}"
  image_id               = local.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name == "" ? null : var.key_name
  update_default_version = true
  # gzip keeps the cloud-init well inside the 16 KB limit, with room for a
  # proxy and a long block list; cloud-init unpacks it. Terraform's gzip is
  # deterministic, so an unchanged cloud-init does not roll the instances.
  user_data = base64gzip(local.user_data)

  iam_instance_profile {
    arn = local.create_role ? aws_iam_instance_profile.this[0].arn : var.existing_instance_profile_arn
  }

  # No public address: the subnets' routes give the way out.
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = concat([local.security_group_id], var.additional_security_group_ids)
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

    # 16 KB of user data is 21848 characters in base64.
    precondition {
      condition     = length(base64gzip(local.user_data)) <= 21848
      error_message = "The compressed cloud-init is larger than the 16 KB EC2 user data limit. Shorten sandbox_blocked_destinations, no_proxy, trusted_ca_certificates or custom_ca_certificate."
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

  # The role's policies are in place before an instance boots and pulls.
  depends_on = [
    aws_iam_role_policy.this,
    aws_iam_role_policy_attachment.this,
  ]

  lifecycle {
    precondition {
      condition     = var.instance_refresh_max_healthy_percentage - var.instance_refresh_min_healthy_percentage <= 100
      error_message = "instance_refresh_max_healthy_percentage may be at most 100 above instance_refresh_min_healthy_percentage."
    }
  }
}
