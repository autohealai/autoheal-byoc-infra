# Both providers log in to the cluster with an exec plugin that fetches a short
# lived token at plan and apply time, so no kubeconfig, token or client key is
# written to state:
#
#   azure  kubelogin get-token (the Entra ID login of an AKS cluster). The login
#          mode comes from kubelogin_login_mode: azurecli after `az login` in a
#          pipeline, workloadidentity for federated pipeline identities, spn or
#          msi otherwise. kubelogin must be on the PATH.
#   aws    aws eks get-token. The AWS CLI must be on the PATH and the pipeline's
#          AWS credentials must map to a cluster access entry.

locals {
  # Server ID of the AKS AAD server application. The same in every tenant.
  aks_aad_server_id = "6dae42f8-4368-4678-94ff-3960e28e3630"

  exec = var.cluster.cloud == "azure" ? {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = ["get-token", "--login", var.kubelogin_login_mode, "--server-id", local.aks_aad_server_id]
    } : {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster.name, "--region", var.cluster.region, "--output", "json"]
  }

  # The infra compositions output the CA certificate base64 encoded, as the cloud
  # APIs return it.
  cluster_ca_certificate = var.cluster.ca_certificate == "" ? null : base64decode(var.cluster.ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = var.cluster.endpoint
    cluster_ca_certificate = local.cluster_ca_certificate
    exec                   = local.exec
  }
}

provider "kubernetes" {
  host                   = var.cluster.endpoint
  cluster_ca_certificate = local.cluster_ca_certificate

  exec {
    api_version = local.exec.api_version
    command     = local.exec.command
    args        = local.exec.args
  }
}
