# The public path of compositions/azure (cluster_network_path = public): the
# runner VMs reach the cluster over the internet, not through a VNet. The infra
# values turn off the chart's internal load balancers for Temporal and the
# api-server-go tool-response listener; here they get public load balancers on
# the static public IP from the temporal_public_endpoint output, open only to
# the runner's NAT address. Both share the IP on different ports, as the
# internal ones do.
#
# externalTrafficPolicy Local keeps the runner's address, so the network
# policies can let in only that address. The chart's own policies admit
# traffic from inside the namespace only.

locals {
  public_services = var.temporal_public_endpoint == null ? {} : {
    temporal-frontend-public = {
      selector    = { "app.kubernetes.io/name" = "temporal", "app.kubernetes.io/instance" = var.release_name, "app.kubernetes.io/component" = "frontend" }
      port_name   = "grpc-rpc"
      port        = 7233
      target_port = "rpc"
    }
    api-server-go-public = {
      selector    = { "app.kubernetes.io/name" = "api-server-go", "app.kubernetes.io/instance" = var.release_name }
      port_name   = "internal"
      port        = 8083
      target_port = "8083"
    }
  }
}

resource "kubernetes_service_v1" "public" {
  for_each = local.public_services

  metadata {
    name      = each.key
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-ipv4" = var.temporal_public_endpoint.ip
    }
  }

  spec {
    type                        = "LoadBalancer"
    external_traffic_policy     = "Local"
    load_balancer_source_ranges = var.temporal_public_endpoint.allowed_source_ranges
    selector                    = each.value.selector

    port {
      name        = each.value.port_name
      port        = each.value.port
      target_port = each.value.target_port
      protocol    = "TCP"
    }
  }

  depends_on = [helm_release.autoheal]
}

resource "kubernetes_network_policy_v1" "public" {
  for_each = local.public_services

  metadata {
    name      = each.key
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = each.value.selector
    }
    policy_types = ["Ingress"]

    ingress {
      dynamic "from" {
        for_each = var.temporal_public_endpoint.allowed_source_ranges
        content {
          ip_block {
            cidr = from.value
          }
        }
      }
      ports {
        port     = tostring(each.value.port)
        protocol = "TCP"
      }
    }
  }

  depends_on = [helm_release.autoheal]
}
