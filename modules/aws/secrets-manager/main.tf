# Secrets Manager storage for a BYOC-on-EKS Autoheal install. Creates one secret
# per entry in var.secrets under a shared prefix (e.g. tenants/<tenant>/<key>). The
# app reads them via its IRSA role (modules/aws/irsa), which is granted
# GetSecretValue on the prefix; nothing here grants read access itself.
#
# Azure analogue: modules/azure/keyvault (one Key Vault, secrets as children).
# Naming/tags via the null-label base (module.this); see label.tf.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# for_each needs non-sensitive keys; var.secrets is sensitive, so unwrap the key
# set only (values stay sensitive and flow to secret_string below).
resource "aws_secretsmanager_secret" "this" {
  for_each = nonsensitive(toset(keys(var.secrets)))

  name                    = "${var.secret_prefix}/${each.value}"
  description             = "Autoheal ${each.value}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(module.this.tags, { Name = "${var.secret_prefix}/${each.value}" })
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = nonsensitive(toset(keys(var.secrets)))

  secret_id     = aws_secretsmanager_secret.this[each.value].id
  secret_string = var.secrets[each.value]
}
