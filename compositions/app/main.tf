# The Autoheal chart, installed with the infra composition's autoheal_values and
# the customer's values-customer.yaml. The values list keeps the order of two -f
# flags, so the chart's merge rules are the same as for a Helm or Flux install:
#
#   helm upgrade --install autoheal oci://public.ecr.aws/e4h3h0d9/charts/autoheal \
#     --version <chart_version> -n autoheal --create-namespace \
#     -f values-infra.yaml -f values-customer.yaml --atomic --wait --timeout 20m
#
# The state holds the release and its values. Neither holds a secret: the chart
# reads secrets from the vault at run time.

locals {
  # A chart_repository that is not a URL is a local chart directory or .tgz.
  chart_is_local = !can(regex("^(oci|https?)://", var.chart_repository))
}

resource "helm_release" "autoheal" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = true

  repository = local.chart_is_local ? null : var.chart_repository
  chart      = local.chart_is_local ? var.chart_repository : "autoheal"
  # A local chart is used as it is; its Chart.yaml carries the version.
  version = local.chart_is_local ? null : var.chart_version

  values = compact([yamlencode(var.infra_values), var.customer_values])

  atomic  = true
  wait    = true
  timeout = var.timeout
}
