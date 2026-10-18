terraform {
  required_version = ">= 1.7"

  # Provider pins only. This is the one composition with the helm and kubernetes
  # providers; the cloud compositions have neither.
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}
