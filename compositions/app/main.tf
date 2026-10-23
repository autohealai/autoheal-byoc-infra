locals {
  # A chart_repository that is not a URL is a local chart directory or .tgz.
  chart_is_local = !can(regex("^(oci|https?)://", var.chart_repository))

  lbc         = var.aws_load_balancer_controller
  install_lbc = var.cluster.cloud == "aws" && local.lbc.enabled
}

# The AWS Load Balancer Controller, on EKS in loadbalancer mode only. The chart
# binds the proxy Service to the infra composition's edge NLB target groups with
# TargetGroupBinding objects, and this controller registers the pod IPs in them. The service account name is the
# one compositions/aws federates (create_load_balancer_controller_role). The
# controller only serves TargetGroupBinding here: no IngressClass, no Service
# webhook, no WAF or Shield, which its role does not allow anyway.
resource "helm_release" "aws_load_balancer_controller" {
  count = local.install_lbc ? 1 : 0

  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = local.lbc.repository
  chart      = "aws-load-balancer-controller"
  version    = local.lbc.chart_version

  values = compact([
    yamlencode({
      clusterName                 = var.cluster.name
      region                      = var.cluster.region
      vpcId                       = var.cluster.vpc_id
      serviceAccount              = { create = true, name = "aws-load-balancer-controller" }
      replicaCount                = 2
      podDisruptionBudget         = { maxUnavailable = 1 }
      createIngressClassResource  = false
      ingressClassParams          = { create = false }
      enableServiceMutatorWebhook = false
      enableShield                = false
      enableWaf                   = false
      enableWafv2                 = false
    }),
    local.lbc.values,
  ])

  atomic  = true
  wait    = true
  timeout = 600

  lifecycle {
    precondition {
      condition     = var.cluster.vpc_id != ""
      error_message = "cluster.vpc_id is required for the AWS Load Balancer Controller: the pods cannot read it from instance metadata. Pass the cluster output of compositions/aws, which includes it."
    }
  }
}

resource "helm_release" "autoheal" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = var.create_namespace

  repository = local.chart_is_local ? null : var.chart_repository
  chart      = local.chart_is_local ? var.chart_repository : "autoheal"
  version    = local.chart_is_local ? null : var.chart_version

  values = compact([yamlencode(var.infra_values), var.customer_values])

  atomic  = true
  wait    = true
  timeout = var.timeout

  # The TargetGroupBinding CRD and its webhook must be up before the chart
  # installs, and on destroy the controller must outlive the bindings to remove
  # their finalizers.
  depends_on = [helm_release.aws_load_balancer_controller]
}
