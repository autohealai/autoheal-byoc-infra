# The cloud resources: VPC, EKS, Aurora PostgreSQL, ElastiCache, S3, KMS,
# Secrets Manager, Pod Identity roles, the edge NLB and the DNS records. The
# source line reads the infra tag from versions.hcl, so this file does not
# change on upgrade.

locals { v = read_terragrunt_config(find_in_parent_folders("versions.hcl")).locals }

include "root" { path = find_in_parent_folders("root.hcl") }

# Our code, pinned to the tag in versions.hcl. To try changes from a local
# checkout instead: source = "/path/to/autoheal-byoc-infra//compositions/aws"
terraform {
  source = "git::https://github.com/autohealai/autoheal-byoc-infra.git//compositions/aws?ref=v${local.v.infra_version}"
}

inputs = {
  namespace   = "acme"
  environment = "prod"
  account_id  = "111111111111"
  region      = "us-west-2"

  # We never create a hosted zone, only the records in it. If the zone is not
  # in Route 53 (Cloudflare, Infoblox), remove this line and set
  # create_dns_records = false; the required_dns_records output then lists the
  # records for your DNS team.
  existing_dns_zone_id = "Z0123456789ABCDEFGHIJ"

  # With nothing below set, we create everything else, with a new VPC in this
  # range across three zones and a NAT gateway per zone.
  network_cidr = "10.60.0.0/16"

  # Things you already have. Uncomment the ones you bring; anything not listed,
  # we create. A brought resource is only read, never changed.
  #
  # existing_network = {
  #   vpc_id             = "vpc-0123456789abcdef0"
  #   private_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2", "subnet-0aaaaaaaaaaaaaaa3"] # nodes, pods, an internal edge NLB
  #   data_subnet_ids    = ["subnet-0bbbbbbbbbbbbbbb1", "subnet-0bbbbbbbbbbbbbbb2", "subnet-0bbbbbbbbbbbbbbb3"] # Aurora and ElastiCache we create; empty means private_subnet_ids
  #   # node_security_group_id = "sg-0123456789abcdef0" # when the nodes do not use the cluster security group
  # }
  #
  # existing_eks_cluster_arn        = "arn:aws:eks:us-west-2:111111111111:cluster/platform"
  # existing_postgres_arn           = "arn:aws:rds:us-west-2:111111111111:cluster:platform-pg" # an Aurora cluster or an RDS instance (:db:)
  # existing_redis_arn              = "arn:aws:elasticache:us-west-2:111111111111:replicationgroup:platform-redis"
  # existing_attachments_bucket_arn = "arn:aws:s3:::acme-autoheal-attachments"
  # existing_artifacts_bucket_arn   = "arn:aws:s3:::acme-autoheal-artifacts"
  # existing_kms_key_arn            = "arn:aws:kms:us-west-2:111111111111:key/1234abcd-12ab-44cd-a6ef-1234567890ab"
  # existing_registry_url           = "111111111111.dkr.ecr.us-west-2.amazonaws.com/autoheal" # a mirror of the Autoheal images
  #
  # With existing_postgres_arn, pass the database's master password as
  # TF_VAR_postgres_admin_password from the pipeline's secret store. With
  # existing_redis_arn (AUTH must be on), pass TF_VAR_redis_auth_token.

  # Pod Identity associations. true: Terraform creates them. false: an
  # administrator runs the commands in the required_role_assignments output,
  # and the workloads cannot reach AWS until they exist.
  # create_pod_identity_associations = false
  # iam_permissions_boundary_arn     = "arn:aws:iam::111111111111:policy/platform-boundary"

  # Who may use the cluster besides the identity running the apply. Name IAM
  # Identity Center permission sets that are assigned to this account; people
  # then log in with `aws sso login`. Admins get AmazonEKSClusterAdminPolicy,
  # viewers AmazonEKSViewPolicy (workloads and pod logs, no Secrets). List IAM
  # roles by ARN instead, such as a break-glass role for when Identity Center
  # is unavailable.
  cluster_admin_sso_permission_sets  = ["AutohealAdmin"]
  cluster_viewer_sso_permission_sets = ["AutohealReadOnly"]
  # cluster_admin_principal_arns     = ["arn:aws:iam::111111111111:role/break-glass"]
  # cluster_viewer_principal_arns    = ["arn:aws:iam::111111111111:role/support"]

  # From where the API server is reachable. Set private_cluster_enabled = true
  # when the pipeline runs inside the VPC.
  api_server_authorized_ip_ranges = ["203.0.113.10/32"]

  # Sizing
  eks_node_instance_types = ["m7i.xlarge"]
  eks_node_count          = 3
  postgres_instance_class = "db.r7g.large"

  # The name users open in a browser. Terraform creates its DNS record and passes
  # it to the app. Login is at auth.autoheal.acme.example and auth-app at
  # auth-app.autoheal.acme.example unless auth_hostname or auth_app_hostname is
  # set.
  hostname = "autoheal.acme.example"

  # How traffic reaches the Autoheal proxy. loadbalancer: we create an NLB for it
  # and point DNS there. It needs no Ingress controller, Gateway or Istio. Use
  # gateway-api, istio or ingress only when the cluster already runs one, and set
  # edge_address to that edge's address so the DNS records point there.
  edge_mode     = "loadbalancer"
  edge_exposure = "internal" # internet-facing needs edge_allowed_cidr_blocks
  # edge_mode    = "ingress"
  # edge_address = "k8s-ingress-0123456789.elb.us-west-2.amazonaws.com"

  # Models through Bedrock with the agents' Pod Identity roles, so no API key.
  # For another provider, set this to false and pass TF_VAR_llm_api_key.
  bedrock_access_enabled = true

  # The LLM API key and every other secret are not in this file. The pipeline
  # passes them as TF_VAR_* and Terraform stores them in Secrets Manager; see
  # the README.
}
