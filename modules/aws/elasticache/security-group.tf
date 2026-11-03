# The cache's own security group. Ingress on the cache port only, from the
# allowed security groups and CIDR blocks. No egress rules: Terraform removes the
# default allow-all egress rule, and the cache needs no outbound connections.
#
# Security group IDs are often created in the same apply, so their values are
# unknown at plan time. The rules are indexed by position (count over the list
# length, which is known) rather than keyed by value. CIDR blocks come from
# configuration and are keyed by value.
#
# With security_group_ids the cache uses those groups instead: we create no
# security group and no rule, so their owner allows the cache port.
# allowed_security_group_ids and allowed_cidr_blocks are then not used.

resource "aws_security_group" "this" {
  count = local.create_security_group ? 1 : 0

  name_prefix = "${local.replication_group_id}-"
  description = "ElastiCache ${local.replication_group_id}"
  vpc_id      = var.vpc_id

  tags = merge(module.this.tags, { Name = local.replication_group_id })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  count = local.create_security_group ? length(var.allowed_security_group_ids) : 0

  security_group_id            = aws_security_group.this[0].id
  description                  = "Cache from an allowed security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = var.allowed_security_group_ids[count.index]

  tags = module.this.tags
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr_blocks" {
  for_each = toset(local.create_security_group ? var.allowed_cidr_blocks : [])

  security_group_id = aws_security_group.this[0].id
  description       = "Cache from an allowed CIDR block"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = module.this.tags
}

locals {
  create_security_group = length(var.security_group_ids) == 0
  security_group_ids    = local.create_security_group ? [aws_security_group.this[0].id] : var.security_group_ids
}

# Before 4.4.0 the security group had no count.
moved {
  from = aws_security_group.this
  to   = aws_security_group.this[0]
}
