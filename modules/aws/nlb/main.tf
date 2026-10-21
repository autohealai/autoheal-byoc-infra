# Network Load Balancer with one TCP listener and one target group per entry in
# var.listeners. The Azure analogue is the internal load balancer the chart
# pins to a reserved address.
#
# Target groups use target_type ip and the module registers no targets: the AWS
# Load Balancer Controller registers pod IPs through the TargetGroupBinding
# resources the chart renders from target_group_arns. Client IP preservation
# stays off (the ip target default), so targets see the load balancer's own
# address. That avoids the connection hangs seen when a client and its target
# sit behind the same NLB in one subnet.
#
# The NLB has its own security group. Ingress allows each listener port from
# allowed_cidr_blocks and allowed_security_group_ids; egress allows the target
# and health check ports to the VPC CIDR. When target_security_group_ids is set
# (for example the EKS cluster security group), those groups get an ingress
# rule from the NLB security group on the same ports. Security group rules are
# keyed by list position, not by ID, so IDs created in the same apply can be
# passed in.
#
# Naming and tags come from the null-label base (module.this); see label.tf.
# NLB and target group names are limited to 32 characters and are cut with a
# short hash suffix.

locals {
  listeners = {
    for k, l in var.listeners : k => {
      port                 = l.port
      target_port          = coalesce(l.target_port, l.port)
      protocol             = l.protocol
      deregistration_delay = l.deregistration_delay
      health_check         = l.health_check
    }
  }

  # NLB names: at most 32 characters, letters, digits and hyphens.
  lb_name = length(module.this.id) <= 32 ? module.this.id : "${trim(substr(module.this.id, 0, 25), "-")}-${substr(md5(module.this.id), 0, 6)}"

  # Target group names always end in a hash of the settings that force a new
  # target group, so a replacement gets a new name and can be created before
  # the old one is deleted (the listener still points at the old one).
  tg_names = {
    for k, l in local.listeners : k => format("%s-%s",
      trim(substr(replace(replace("${module.this.id}-${k}", "/[^a-zA-Z0-9-]/", "-"), "/-+/", "-"), 0, 27), "-"),
      substr(md5("${module.this.id}/${k}/${l.target_port}/${l.protocol}/${var.vpc_id}"), 0, 4),
    )
  }

  # Ports the NLB sends traffic and health checks to.
  target_ports = distinct(concat(
    [for l in values(local.listeners) : l.target_port],
    [for l in values(local.listeners) : tonumber(l.health_check.port) if l.health_check.port != "traffic-port"],
  ))

  ingress_cidr_rules = {
    for p in setproduct(keys(local.listeners), range(length(var.allowed_cidr_blocks))) :
    "${p[0]}/${p[1]}" => { listener = p[0], index = p[1] }
  }

  ingress_sg_rules = {
    for p in setproduct(keys(local.listeners), range(length(var.allowed_security_group_ids))) :
    "${p[0]}/${p[1]}" => { listener = p[0], index = p[1] }
  }

  target_sg_rules = {
    for p in setproduct(range(length(var.target_security_group_ids)), local.target_ports) :
    "${p[0]}/${p[1]}" => { index = p[0], port = p[1] }
  }
}

resource "aws_security_group" "this" {
  name        = "${module.this.id}-nlb"
  description = "Network load balancer ${module.this.id}"
  vpc_id      = var.vpc_id

  tags = merge(module.this.tags, { Name = "${module.this.id}-nlb" })
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = local.ingress_cidr_rules

  security_group_id = aws_security_group.this.id
  description       = "Listener ${each.value.listener}"
  ip_protocol       = "tcp"
  from_port         = local.listeners[each.value.listener].port
  to_port           = local.listeners[each.value.listener].port
  cidr_ipv4         = var.allowed_cidr_blocks[each.value.index]

  tags = module.this.tags
}

resource "aws_vpc_security_group_ingress_rule" "security_group" {
  for_each = local.ingress_sg_rules

  security_group_id            = aws_security_group.this.id
  description                  = "Listener ${each.value.listener}"
  ip_protocol                  = "tcp"
  from_port                    = local.listeners[each.value.listener].port
  to_port                      = local.listeners[each.value.listener].port
  referenced_security_group_id = var.allowed_security_group_ids[each.value.index]

  tags = module.this.tags
}

resource "aws_vpc_security_group_egress_rule" "targets" {
  for_each = { for p in local.target_ports : tostring(p) => p }

  security_group_id = aws_security_group.this.id
  description       = "Targets and health checks on port ${each.value}"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = var.vpc_cidr_block

  tags = module.this.tags
}

resource "aws_vpc_security_group_ingress_rule" "targets" {
  for_each = local.target_sg_rules

  security_group_id            = var.target_security_group_ids[each.value.index]
  description                  = "From ${local.lb_name} on port ${each.value.port}"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = aws_security_group.this.id

  tags = module.this.tags
}

resource "aws_lb" "this" {
  name               = local.lb_name
  load_balancer_type = "network"
  internal           = var.internal
  ip_address_type    = "ipv4"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.this.id]

  enable_cross_zone_load_balancing = var.cross_zone_enabled
  enable_deletion_protection       = var.deletion_protection

  # NLB access logs only record TLS listeners, so with TCP listeners the bucket
  # stays empty. Kept for when a TLS listener is added.
  access_logs {
    enabled = var.access_logs_bucket != ""
    bucket  = var.access_logs_bucket
    prefix  = var.access_logs_prefix == "" ? null : var.access_logs_prefix
  }

  tags = module.this.tags
}

resource "aws_lb_target_group" "this" {
  for_each = local.listeners

  name                 = local.tg_names[each.key]
  vpc_id               = var.vpc_id
  target_type          = "ip"
  ip_address_type      = "ipv4"
  port                 = each.value.target_port
  protocol             = each.value.protocol
  deregistration_delay = each.value.deregistration_delay
  preserve_client_ip   = false

  health_check {
    enabled             = true
    protocol            = each.value.health_check.protocol
    port                = each.value.health_check.port
    path                = each.value.health_check.protocol == "TCP" ? null : coalesce(each.value.health_check.path, "/")
    interval            = each.value.health_check.interval
    timeout             = min(each.value.health_check.protocol == "HTTP" ? 6 : 10, each.value.health_check.interval - 1)
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  tags = merge(module.this.tags, { Name = local.tg_names[each.key] })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "this" {
  for_each = local.listeners

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = each.value.protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  tags = module.this.tags
}
