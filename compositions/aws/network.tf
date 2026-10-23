# VPC: the network we create, or the customer's (existing_network).
#
# We create, per availability zone: a private subnet for nodes, pods and an
# internal edge load balancer; a data subnet for Aurora and ElastiCache with no
# route to the internet; and a public subnet for the NAT gateways and an
# internet-facing edge load balancer. VPC flow logs go to CloudWatch, encrypted
# with the logs key. The S3 gateway endpoint is always there; interface
# endpoints for the AWS APIs are optional (private_endpoints_enabled).
#
# For a brought network we read only the VPC CIDR, which the load balancer
# security groups use. Its subnets need routes to the internet or to VPC
# endpoints for ECR, STS, Secrets Manager, KMS and EKS.

module "vpc" {
  source = "../../modules/aws/vpc"
  count  = local.create_network ? 1 : 0

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  tags        = var.tags

  cidr_block           = var.network_cidr
  availability_zones   = local.azs
  private_subnet_cidrs = local.created_subnets.private
  data_subnet_cidrs    = local.created_subnets.data
  public_subnet_cidrs  = local.created_subnets.public
  nat_gateway_mode     = var.nat_gateway_mode

  # Subnet tags for the cluster we create in it.
  cluster_name = local.create_cluster ? local.cluster_create_name : ""

  flow_logs_enabled        = true
  flow_logs_retention_days = var.log_retention_days
  flow_logs_kms_key_arn    = local.kms_key_arns.logs

  s3_gateway_endpoint_enabled = true
  interface_endpoints         = var.private_endpoints_enabled ? var.private_endpoint_services : []
}

data "aws_vpc" "existing" {
  count = local.create_network ? 0 : 1
  id    = var.existing_network.vpc_id
}
