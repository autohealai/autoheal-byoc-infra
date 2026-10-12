# AWS network substrate for a BYOC-on-EKS install. The Azure analogue is
# modules/azure/vnet. Provides:
#   - VPC with DNS support.
#   - Public + private subnets, one pair per AZ (sized by cidrsubnet).
#   - Internet Gateway for the public tier.
#   - One NAT gateway per AZ (private egress; stable source IPs for allowlisting).
#   - EKS discovery tags on the subnets (kubernetes.io/role/{elb,internal-elb} and
#     the per-cluster shared tag) so the ALB/NLB controllers place load balancers.
#
# Naming and tags come from the null-label base (module.this); see label.tf. The
# cluster name for the discovery tags is passed in (the composition derives the same
# id the eks module uses), since subnet tags must exist at cluster-create time.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(module.this.tags, { Name = module.this.id })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(module.this.tags, { Name = "${module.this.id}-igw" })
}

# Public subnets host the IGW-facing tier (NAT gateways, and the ALB when the edge
# is public); auto-assigning public IPs is required there. Workloads run in the
# private subnets (map_public_ip_on_launch defaults to false).
#trivy:ignore:AVD-AWS-0164 Public-tier subnets (NAT/ALB) require auto-assigned public IPs; workloads are in private subnets.
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(module.this.tags, {
    Name                                        = "${module.this.id}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + length(var.availability_zones))
  availability_zone = var.availability_zones[count.index]

  tags = merge(module.this.tags, {
    Name                                        = "${module.this.id}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"
  tags   = merge(module.this.tags, { Name = "${module.this.id}-nat-eip-${var.availability_zones[count.index]}" })
}

resource "aws_nat_gateway" "this" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags       = merge(module.this.tags, { Name = "${module.this.id}-nat-${var.availability_zones[count.index]}" })
  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(module.this.tags, { Name = "${module.this.id}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = merge(module.this.tags, { Name = "${module.this.id}-private-rt-${var.availability_zones[count.index]}" })
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
