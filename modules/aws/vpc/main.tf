# AWS network for a BYOC-on-EKS install. The Azure analogue is modules/azure/vnet.
#
# Subnet tiers, one subnet per availability zone in each tier:
#   - public:  NAT gateways and internet-facing load balancers. No auto-assigned
#              public IPs; nothing else should run here.
#   - private: EKS control plane ENIs, nodes and pods. Default route to NAT.
#   - data:    Aurora and ElastiCache (optional). Its route table has no internet
#              route at all.
#
# Route tables carry standalone aws_route resources (no inline routes), so a
# caller can add its own routes (peering, transit gateway) without Terraform
# removing them.
#
# All counts come from list lengths and plain variables, never from resource
# attributes, so every plan is complete before apply.
#
# Naming and tags come from the null-label base (module.this); see label.tf.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  az_count = length(var.availability_zones)

  nat_count = (
    var.nat_gateway_mode == "per_az" ? local.az_count :
    var.nat_gateway_mode == "single" ? 1 : 0
  )

  data_subnets_enabled = length(var.data_subnet_cidrs) > 0

  # kubernetes.io/cluster/<name>=shared marks the subnets as usable by that
  # cluster. Only the public and private tiers get it, so load balancers and
  # nodes never land in the data subnets.
  cluster_tag = var.cluster_name != "" ? { "kubernetes.io/cluster/${var.cluster_name}" = "shared" } : {}
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(module.this.tags, { Name = module.this.id })

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_cidrs) == local.az_count
      error_message = "private_subnet_cidrs must have one CIDR per availability zone (${local.az_count})."
    }

    precondition {
      condition     = length(var.public_subnet_cidrs) == local.az_count
      error_message = "public_subnet_cidrs must have one CIDR per availability zone (${local.az_count})."
    }

    precondition {
      condition     = contains([0, local.az_count], length(var.data_subnet_cidrs))
      error_message = "data_subnet_cidrs must be empty or have one CIDR per availability zone (${local.az_count})."
    }
  }
}

# Strip every rule from the default security group so nothing that falls back to
# it gets any traffic.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(module.this.tags, { Name = "${module.this.id}-default-unused" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(module.this.tags, { Name = "${module.this.id}-igw" })
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(module.this.tags, local.cluster_tag, {
    Name                     = "${module.this.id}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(module.this.tags, local.cluster_tag, {
    Name                              = "${module.this.id}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_subnet" "data" {
  count = length(var.data_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(module.this.tags, {
    Name = "${module.this.id}-data-${var.availability_zones[count.index]}"
  })
}

# -----------------------------------------------------------------------------
# NAT gateways: one per zone (per_az), one in the first zone (single), or none.
# -----------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count = local.nat_count

  domain = "vpc"

  tags = merge(module.this.tags, {
    Name = "${module.this.id}-nat-${var.availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(module.this.tags, {
    Name = "${module.this.id}-nat-${var.availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

# -----------------------------------------------------------------------------
# Route tables
# -----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(module.this.tags, { Name = "${module.this.id}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per zone in every NAT mode, so switching modes only
# changes routes, never subnet associations.
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  tags = merge(module.this.tags, {
    Name = "${module.this.id}-private-${var.availability_zones[count.index]}"
  })
}

resource "aws_route" "private_nat" {
  count = local.nat_count > 0 ? local.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.nat_gateway_mode == "per_az" ? count.index : 0].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# The data tier has no route to the internet in any NAT mode.
resource "aws_route_table" "data" {
  count = local.data_subnets_enabled ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(module.this.tags, { Name = "${module.this.id}-data" })
}

resource "aws_route_table_association" "data" {
  count = length(var.data_subnet_cidrs)

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data[0].id
}
