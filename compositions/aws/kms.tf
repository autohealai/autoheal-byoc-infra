# KMS: one customer-managed key per purpose, or the customer's key for all of
# them (existing_kms_key_arn). See locals.tf for what each key encrypts.
#
# Every key policy starts with the account root statement, so IAM policies in
# this account grant use of the keys: the EKS cluster role, the Aurora and
# ElastiCache services acting for the deployer, and the workload roles in
# identity.tf. The logs key also lets CloudWatch Logs in this region encrypt our
# log groups. The EBS volumes of the nodes use the account's default EBS key,
# which the Auto Scaling service role can always use.

module "kms" {
  source   = "../../modules/aws/kms"
  for_each = local.create_kms ? toset(local.kms_purposes) : toset([])

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
  attributes  = [each.key]
  tags        = var.tags

  description             = "Autoheal ${local.id}: ${local.kms_descriptions[each.key]}"
  key_administrator_arns  = var.kms_key_administrator_arns
  cloudwatch_logs_enabled = each.key == "logs"
}

locals {
  kms_descriptions = {
    eks     = "EKS Kubernetes Secrets"
    data    = "Aurora and ElastiCache at rest"
    storage = "S3 buckets"
    secrets = "Secrets Manager install secrets"
    logs    = "CloudWatch log groups"
  }
}
