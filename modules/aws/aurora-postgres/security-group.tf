# The cluster's own security group. Ingress on the database port only, from the
# allowed security groups and CIDR blocks. No egress rules: Terraform removes the
# default allow-all egress rule, and the cluster needs no outbound connections.
#
# Security group IDs are often created in the same apply, so their values are
# unknown at plan time. The rules are indexed by position (count over the list
# length, which is known) rather than keyed by value. CIDR blocks come from
# configuration and are keyed by value.

resource "aws_security_group" "this" {
  name_prefix = "${local.cluster_identifier}-"
  description = "Aurora PostgreSQL ${local.cluster_identifier}"
  vpc_id      = var.vpc_id

  tags = merge(module.this.tags, { Name = local.cluster_identifier })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from an allowed security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = var.allowed_security_group_ids[count.index]

  tags = module.this.tags
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr_blocks" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL from an allowed CIDR block"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = module.this.tags
}
