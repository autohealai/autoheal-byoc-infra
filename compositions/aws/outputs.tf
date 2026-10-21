# Outputs for the app folder and for people. Same names as compositions/azure
# (docs/MODULE_STANDARD.md section 8).
#
#   autoheal_values            the chart's infra values, as an object
#   autoheal_values_yaml       the same values as YAML text (values-infra.yaml)
#   cluster                    what compositions/app needs to log in to the cluster
#   required_role_assignments  Pod Identity associations an administrator must
#                              create, filled only when
#                              create_pod_identity_associations = false
#   required_dns_records       records a person must create, filled only when we
#                              do not create them
#   required_cluster_owner_actions
#                              what the owner of a brought cluster must do, filled
#                              only for a brought cluster
#   network                   the VPC and subnets Autoheal runs in, created or
#                              brought
#
# None of them holds a secret.

output "autoheal_values" {
  description = "Infra values for the Autoheal chart (global.infra facts, suggestions, and the Temporal and Zitadel copies). Pass to compositions/app as infra_values."
  value       = local.autoheal_values
}

output "autoheal_values_yaml" {
  description = "autoheal_values as YAML, for customers who install with Helm or Flux and commit values-infra.yaml."
  value       = yamlencode(local.autoheal_values)
}

output "cluster" {
  description = "Cluster connection details for compositions/app: cloud, name, region, endpoint, base64 ca_certificate and vpc_id. Authentication is an EKS token from the caller's AWS credentials; no credential is output."
  value = {
    cloud          = "aws"
    name           = local.cluster_name
    region         = var.region
    endpoint       = local.cluster_endpoint
    ca_certificate = local.cluster_ca_certificate
    vpc_id         = local.vpc_id
  }
}

output "required_role_assignments" {
  description = "Pod Identity associations an administrator must create, as commands. Filled only when create_pod_identity_associations = false; the workloads cannot reach AWS until they exist."
  value = var.create_pod_identity_associations ? [] : [
    for b in local.role_bindings :
    "aws eks create-pod-identity-association --region ${var.region} --cluster-name ${local.cluster_name} --namespace ${b.ns} --service-account ${b.sa} --role-arn ${b.role}"
  ]
}

output "required_dns_records" {
  description = "DNS records a person must create (name, type, value). Filled when create_dns_records = false, when existing_dns_zone_id is empty, or when the address is not known yet (edge_address empty in a mode other than loadbalancer)."
  value       = local.required_dns_records
}

output "required_cluster_owner_actions" {
  description = "What the owner of a brought EKS cluster must do, as readable lines: the deployer's access entry and IAM permissions, the Pod Identity agent and Secrets Store CSI add-ons, the AWS Load Balancer Controller and, when they apply, a path to a private API endpoint and image pull access for the nodes. Filled only when existing_eks_cluster_arn is set."
  value       = local.cluster_owner_actions
}

output "network" {
  description = "The VPC and subnets Autoheal runs in: vpc_id, vpc_cidr_block, private_subnet_ids, runner_subnet_ids, data_subnet_ids and public_subnet_ids. For a brought network these are the IDs passed in existing_network, with the runner and data subnets falling back to the private ones."
  value = {
    vpc_id             = local.vpc_id
    vpc_cidr_block     = local.vpc_cidr_block
    private_subnet_ids = local.private_subnet_ids
    runner_subnet_ids  = local.runner_subnet_ids
    data_subnet_ids    = local.data_subnet_ids
    public_subnet_ids  = local.public_subnet_ids
  }
}
