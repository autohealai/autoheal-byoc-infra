# Plans of compositions/app against mocked providers: which login command each
# cloud gets, where the chart comes from, what the release passes to Helm, and the
# input checks. Nothing here reaches a cluster.

mock_provider "helm" {
  # metadata is filled by Helm after the install. (OpenTofu needs every attribute
  # of a mocked object.)
  mock_resource "helm_release" {
    defaults = {
      metadata = {
        app_version    = "1.0.0"
        chart          = "autoheal"
        first_deployed = 1760000000
        last_deployed  = 1760000000
        name           = "autoheal"
        namespace      = "autoheal"
        notes          = ""
        revision       = 1
        values         = "{}"
        version        = "1.0.0"
      }
    }
  }
}

mock_provider "kubernetes" {}

variables {
  cluster = {
    cloud          = "azure"
    name           = "acme-prod-autoheal-aks"
    resource_group = "rg-acme-prod-autoheal"
    endpoint       = "https://acme-prod-autoheal-aks.hcp.eastus2.azmk8s.io:443"
    ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
  }
  infra_values = {
    global = {
      infra = {
        version = "2.0.0"
        cloud   = "azure"
        hosts   = { app = "autoheal.acme.example", auth = "auth.autoheal.acme.example", authApp = "auth-app.autoheal.acme.example" }
      }
    }
  }
  customer_values = "global:\n  edge:\n    mode: loadbalancer\n"
  chart_version   = "1.0.0"
}

run "aks_from_the_public_registry" {
  command = plan

  assert {
    condition     = local.exec.command == "kubelogin"
    error_message = "AKS logs in with kubelogin."
  }
  assert {
    condition     = local.exec.args == tolist(["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"])
    error_message = "kubelogin get-token with the azurecli login and the AKS server ID."
  }
  assert {
    condition     = local.cluster_ca_certificate == "-----BEGIN CERTIFICATE-----\n"
    error_message = "The CA certificate is base64 decoded for the providers."
  }
  assert {
    condition     = helm_release.autoheal.repository == "oci://public.ecr.aws/e4h3h0d9/charts"
    error_message = "The chart comes from the public registry by default."
  }
  assert {
    condition     = helm_release.autoheal.chart == "autoheal" && helm_release.autoheal.version == "1.0.0"
    error_message = "Chart autoheal at chart_version."
  }
  assert {
    condition     = helm_release.autoheal.name == "autoheal" && helm_release.autoheal.namespace == "autoheal" && helm_release.autoheal.create_namespace
    error_message = "Release autoheal in namespace autoheal, created when missing."
  }
  assert {
    condition     = helm_release.autoheal.atomic && helm_release.autoheal.wait && helm_release.autoheal.timeout == 1200
    error_message = "atomic, wait and a 1200 second timeout."
  }
  assert {
    condition     = length(helm_release.autoheal.values) == 2
    error_message = "Two values documents: infra then customer."
  }
  assert {
    condition     = helm_release.autoheal.values[0] == yamlencode(var.infra_values)
    error_message = "The infra values come first."
  }
  assert {
    condition     = helm_release.autoheal.values[1] == var.customer_values
    error_message = "The customer values come second, so they merge over the suggestions."
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.release_name == "autoheal" && output.namespace == "autoheal"
    error_message = "release_name and namespace outputs."
  }
  assert {
    condition     = output.chart_version == "1.0.0" && output.revision == 1
    error_message = "chart_version and revision come from the release metadata."
  }
}

run "eks" {
  command = plan

  variables {
    cluster = {
      cloud          = "aws"
      name           = "acme-prod-autoheal"
      region         = "us-east-1"
      endpoint       = "https://ABCDEF0123456789.gr7.us-east-1.eks.amazonaws.com"
      ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
    }
  }

  assert {
    condition     = local.exec.command == "aws"
    error_message = "EKS logs in with the AWS CLI."
  }
  assert {
    condition     = local.exec.args == tolist(["eks", "get-token", "--cluster-name", "acme-prod-autoheal", "--region", "us-east-1", "--output", "json"])
    error_message = "aws eks get-token for the cluster and its region."
  }
}

run "eks_with_lb_controller" {
  command = plan

  variables {
    cluster = {
      cloud          = "aws"
      name           = "acme-prod-autoheal"
      region         = "us-east-1"
      vpc_id         = "vpc-0123456789abcdef0"
      endpoint       = "https://ABCDEF0123456789.gr7.us-east-1.eks.amazonaws.com"
      ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
    }
    aws_load_balancer_controller = {
      enabled = true
      values  = "image:\n  repository: 602401143452.dkr.ecr.us-east-1.amazonaws.com/amazon/aws-load-balancer-controller\n"
    }
  }

  assert {
    condition     = length(helm_release.aws_load_balancer_controller) == 1
    error_message = "The controller is installed on EKS when enabled."
  }
  assert {
    condition = (
      helm_release.aws_load_balancer_controller[0].namespace == "kube-system" &&
      helm_release.aws_load_balancer_controller[0].chart == "aws-load-balancer-controller" &&
      helm_release.aws_load_balancer_controller[0].repository == "https://aws.github.io/eks-charts" &&
      helm_release.aws_load_balancer_controller[0].version == "3.6.0"
    )
    error_message = "aws-load-balancer-controller 3.6.0 from eks-charts in kube-system."
  }
  assert {
    condition = (
      yamldecode(helm_release.aws_load_balancer_controller[0].values[0]).clusterName == "acme-prod-autoheal" &&
      yamldecode(helm_release.aws_load_balancer_controller[0].values[0]).region == "us-east-1" &&
      yamldecode(helm_release.aws_load_balancer_controller[0].values[0]).vpcId == "vpc-0123456789abcdef0"
    )
    error_message = "Cluster name, region and VPC come from the cluster input, so the pods need no instance metadata."
  }
  assert {
    condition     = yamldecode(helm_release.aws_load_balancer_controller[0].values[0]).serviceAccount.name == "aws-load-balancer-controller"
    error_message = "The service account compositions/aws federates."
  }
  assert {
    condition = (
      !yamldecode(helm_release.aws_load_balancer_controller[0].values[0]).createIngressClassResource &&
      !yamldecode(helm_release.aws_load_balancer_controller[0].values[0]).enableServiceMutatorWebhook
    )
    error_message = "No IngressClass and no Service webhook: the controller serves TargetGroupBinding only."
  }
  assert {
    condition     = length(helm_release.aws_load_balancer_controller[0].values) == 2
    error_message = "The values override is merged after the composition's settings."
  }
}

run "lb_controller_off_by_default" {
  command = plan

  variables {
    cluster = {
      cloud          = "aws"
      name           = "acme-prod-autoheal"
      region         = "us-east-1"
      endpoint       = "https://ABCDEF0123456789.gr7.us-east-1.eks.amazonaws.com"
      ca_certificate = ""
    }
  }

  assert {
    condition     = length(helm_release.aws_load_balancer_controller) == 0
    error_message = "A cluster that runs its own controller gets none."
  }
}

run "lb_controller_ignored_on_aks" {
  command = plan

  variables {
    aws_load_balancer_controller = { enabled = true }
  }

  assert {
    condition     = length(helm_release.aws_load_balancer_controller) == 0
    error_message = "The AWS controller is never installed on AKS."
  }
}

run "lb_controller_needs_vpc_id" {
  command = plan

  variables {
    cluster = {
      cloud          = "aws"
      name           = "acme-prod-autoheal"
      region         = "us-east-1"
      endpoint       = "https://ABCDEF0123456789.gr7.us-east-1.eks.amazonaws.com"
      ca_certificate = ""
    }
    aws_load_balancer_controller = { enabled = true }
  }

  expect_failures = [helm_release.aws_load_balancer_controller]
}

run "workload_identity_login" {
  command = plan

  variables {
    kubelogin_login_mode = "workloadidentity"
  }

  assert {
    condition     = local.exec.args[2] == "workloadidentity"
    error_message = "kubelogin_login_mode is passed to --login."
  }
}

run "local_chart" {
  command = plan

  variables {
    chart_repository = "../autoheal-chart/charts/autoheal"
  }

  assert {
    condition     = helm_release.autoheal.repository == null
    error_message = "A local chart has no repository."
  }
  assert {
    condition     = helm_release.autoheal.chart == "../autoheal-chart/charts/autoheal"
    error_message = "A local chart path is passed as the chart."
  }
}

run "packaged_local_chart" {
  command = plan

  variables {
    chart_repository = "/work/autoheal-1.1.0-rc.1.tgz"
  }

  assert {
    condition     = helm_release.autoheal.repository == null && helm_release.autoheal.chart == "/work/autoheal-1.1.0-rc.1.tgz"
    error_message = "A packaged chart is used from its path."
  }
}

run "https_repository" {
  command = plan

  variables {
    chart_repository = "https://charts.acme.example/autoheal"
  }

  assert {
    condition     = helm_release.autoheal.repository == "https://charts.acme.example/autoheal" && helm_release.autoheal.chart == "autoheal"
    error_message = "An HTTPS repository is used like the OCI one."
  }
}

run "no_customer_values" {
  command = plan

  variables {
    customer_values = ""
    namespace       = "autoheal-staging"
    release_name    = "autoheal-staging"
  }

  assert {
    condition     = length(helm_release.autoheal.values) == 1
    error_message = "An empty customer_values adds no values document."
  }
  assert {
    condition     = helm_release.autoheal.name == "autoheal-staging" && helm_release.autoheal.namespace == "autoheal-staging"
    error_message = "release_name and namespace are passed through."
  }
}

# A cluster owner gave the deployer one namespace and nothing else, so the
# release must not try to create it.
run "namespace_only_deployer" {
  command = plan

  variables {
    create_namespace = false
  }

  assert {
    condition     = !helm_release.autoheal.create_namespace && helm_release.autoheal.namespace == "autoheal"
    error_message = "create_namespace = false installs into the existing namespace without creating it."
  }
}

# The public path of compositions/azure: Temporal and the tool-response listener
# get public load balancers on the static IP, open to the runner's NAT address.
run "public_temporal_endpoint" {
  command = plan

  variables {
    create_namespace = false
    temporal_public_endpoint = {
      ip                    = "20.30.40.50"
      allowed_source_ranges = ["198.51.100.7/32"]
    }
  }

  assert {
    condition     = length(kubernetes_service_v1.public) == 2 && length(kubernetes_network_policy_v1.public) == 2
    error_message = "Two public load balancers, each with a network policy."
  }
  assert {
    condition = alltrue([
      for s in kubernetes_service_v1.public :
      s.spec[0].type == "LoadBalancer" && s.spec[0].external_traffic_policy == "Local" &&
      tolist(s.spec[0].load_balancer_source_ranges) == tolist(["198.51.100.7/32"]) &&
      s.metadata[0].annotations["service.beta.kubernetes.io/azure-load-balancer-ipv4"] == "20.30.40.50" &&
      s.metadata[0].namespace == "autoheal"
    ])
    error_message = "Both share the static IP, keep the client address and let in only the runner's address."
  }
  assert {
    condition = (
      kubernetes_service_v1.public["temporal-frontend-public"].spec[0].port[0].port == 7233 &&
      kubernetes_service_v1.public["temporal-frontend-public"].spec[0].selector["app.kubernetes.io/component"] == "frontend" &&
      kubernetes_service_v1.public["api-server-go-public"].spec[0].port[0].port == 8083 &&
      kubernetes_service_v1.public["api-server-go-public"].spec[0].selector["app.kubernetes.io/name"] == "api-server-go"
    )
    error_message = "Temporal on 7233 and the tool-response listener on 8083, each selecting the chart's pods."
  }
  assert {
    condition = (
      kubernetes_network_policy_v1.public["temporal-frontend-public"].spec[0].ingress[0].from[0].ip_block[0].cidr == "198.51.100.7/32" &&
      kubernetes_network_policy_v1.public["temporal-frontend-public"].spec[0].ingress[0].ports[0].port == "7233"
    )
    error_message = "The network policy admits the runner's address on the service port."
  }
}

run "public_endpoint_needs_a_source" {
  command = plan

  variables {
    temporal_public_endpoint = {
      ip                    = "20.30.40.50"
      allowed_source_ranges = []
    }
  }

  expect_failures = [var.temporal_public_endpoint]
}

run "no_public_endpoint_by_default" {
  command = plan

  assert {
    condition     = length(kubernetes_service_v1.public) == 0 && length(kubernetes_network_policy_v1.public) == 0
    error_message = "Without temporal_public_endpoint no Service or policy is created."
  }
}

run "unknown_cloud" {
  command = plan

  variables {
    cluster = {
      cloud          = "gcp"
      name           = "acme"
      endpoint       = "https://10.0.0.1"
      ca_certificate = ""
    }
  }

  expect_failures = [var.cluster]
}

run "eks_needs_a_region" {
  command = plan

  variables {
    cluster = {
      cloud          = "aws"
      name           = "acme-prod-autoheal"
      endpoint       = "https://ABCDEF0123456789.gr7.us-east-1.eks.amazonaws.com"
      ca_certificate = ""
    }
  }

  expect_failures = [var.cluster]
}

run "bad_chart_version" {
  command = plan

  variables {
    chart_version = "v1.0"
  }

  expect_failures = [var.chart_version]
}

run "bad_login_mode" {
  command = plan

  variables {
    kubelogin_login_mode = "password"
  }

  expect_failures = [var.kubelogin_login_mode]
}
