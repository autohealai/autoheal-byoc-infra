# Secrets Manager entries for a BYOC-on-EKS Autoheal install: one secret per entry
# in secret_names, named <name_prefix><entry>, encrypted with the caller's KMS
# key. The app reads them through an EKS Pod Identity role
# (modules/aws/pod-identity) granted GetSecretValue on arn_pattern; this module
# grants no access itself.
#
# The Azure analogue is modules/azure/keyvault. Tags come from the null-label base
# (module.this); see label.tf.
#
# secret_values is sensitive and may hold values known only after apply, so
# for_each uses the plain list secret_names and never the map.

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # A multi-Region key (key ID mrk-...) has a replica with the same key ID in
  # every region it is replicated to. Fields: arn, partition, service, region,
  # account, resource.
  kms_key_arn_parts = split(":", var.kms_key_arn)
  kms_key_is_mrk    = strcontains(var.kms_key_arn, ":key/mrk-")
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(var.secret_names)

  name                    = "${var.name_prefix}${each.key}"
  description             = "Autoheal ${each.key}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region = replica.value
      kms_key_id = lookup(
        var.replica_kms_key_arns,
        replica.value,
        local.kms_key_is_mrk ? join(":", concat(slice(local.kms_key_arn_parts, 0, 3), [replica.value], slice(local.kms_key_arn_parts, 4, 6))) : null,
      )
    }
  }

  tags = merge(module.this.tags, { Name = "${var.name_prefix}${each.key}" })

  lifecycle {
    precondition {
      condition     = length("${var.name_prefix}${each.key}") <= 512
      error_message = "Secret name ${var.name_prefix}${each.key} is longer than 512 characters."
    }
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = toset(var.secret_names)

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = var.secret_values[each.key]

  lifecycle {
    precondition {
      condition     = contains(keys(var.secret_values), each.key)
      error_message = "secret_values has no value for ${each.key}."
    }
  }
}
