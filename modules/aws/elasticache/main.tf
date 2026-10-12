# ElastiCache for Redis, node-based (provisioned) replication group. The Azure
# analogue is modules/azure/redis. BYOC posture is node-based/provisioned (not
# Serverless), mirroring the provisioned data tier. num_cache_clusters = 1 is a
# single node; > 1 adds read replicas with Multi-AZ automatic failover for prod HA.
#
# Private: the cache lives in the private subnets and is reachable only from the
# security groups in allowed_sg_ids (the EKS node SG) on 6379. TLS in transit and
# at-rest encryption are on; access is SG-restricted (no auth token by default).
#
# Naming and tags come from the null-label base (module.this); see label.tf.

locals {
  group_id = var.replication_group_id_override != "" ? var.replication_group_id_override : substr(module.this.id, 0, 40)
}

resource "aws_security_group" "redis" {
  name        = "${module.this.id}-sg"
  description = "ElastiCache Redis ${module.this.id}"
  vpc_id      = var.vpc_id

  tags = merge(module.this.tags, { Name = "${module.this.id}-sg" })
}

resource "aws_security_group_rule" "ingress" {
  for_each                 = toset(var.allowed_sg_ids)
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.redis.id
  description              = "Redis from allowed security group"
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr_block]
  security_group_id = aws_security_group.redis.id
  description       = "Allow outbound within VPC"
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.group_id}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(module.this.tags, { Name = "${local.group_id}-subnet-group" })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = local.group_id
  description          = "ElastiCache Redis for ${module.this.id}"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true

  snapshot_window          = var.snapshot_window
  snapshot_retention_limit = var.snapshot_retention_limit
  apply_immediately        = var.apply_immediately

  tags = merge(module.this.tags, { Name = module.this.id })
}
