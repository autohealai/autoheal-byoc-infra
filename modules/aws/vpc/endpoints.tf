# VPC endpoints. The S3 gateway endpoint is free and keeps image layer and
# bucket traffic off the NAT gateways. Interface endpoints let nodes and pods
# reach AWS APIs privately (required when nat_gateway_mode = "none").

data "aws_vpc_endpoint_service" "s3" {
  count = var.s3_gateway_endpoint_enabled ? 1 : 0

  service      = "s3"
  service_type = "Gateway"
}

resource "aws_vpc_endpoint" "s3" {
  count = var.s3_gateway_endpoint_enabled ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = data.aws_vpc_endpoint_service.s3[0].service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.private[*].id, aws_route_table.data[*].id)

  tags = merge(module.this.tags, { Name = "${module.this.id}-s3" })
}

# Looked up per service so the endpoint only uses the zones the service is
# offered in; some services are missing from some zones.
data "aws_vpc_endpoint_service" "interface" {
  for_each = toset(var.interface_endpoints)

  service      = each.key
  service_type = "Interface"
}

resource "aws_security_group" "endpoints" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  name        = "${module.this.id}-vpc-endpoints"
  description = "Interface VPC endpoints: HTTPS from inside the VPC"
  vpc_id      = aws_vpc.this.id

  tags = merge(module.this.tags, { Name = "${module.this.id}-vpc-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.cidr_block

  tags = module.this.tags
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = data.aws_vpc_endpoint_service.interface[each.key].service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.endpoints[0].id]

  subnet_ids = [
    for i, az in var.availability_zones : aws_subnet.private[i].id
    if contains(data.aws_vpc_endpoint_service.interface[each.key].availability_zones, az)
  ]

  tags = merge(module.this.tags, { Name = "${module.this.id}-${each.key}" })

  lifecycle {
    precondition {
      condition     = length(setintersection(data.aws_vpc_endpoint_service.interface[each.key].availability_zones, var.availability_zones)) > 0
      error_message = "The ${each.key} endpoint service is not offered in any of the availability zones ${join(", ", var.availability_zones)}."
    }
  }
}
