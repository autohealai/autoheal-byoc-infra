# Outputs for the network owner, the IAM owner and people.
#
#   autoscaling_group_name          the runner Auto Scaling group
#   launch_template_id              its launch template
#   ami_id                          the AMI the instances run
#   security_group_id               the instances' security group, created or
#                                   brought
#   instance_profile_arn            the instances' profile, created or brought
#   iam_role_arn                    the instance role we create, empty with
#                                   existing_instance_profile_arn
#   subnet_cidrs                    the runner subnets' ranges, the source of
#                                   the network rules
#   required_network_owner_actions  what the network owner must open
#   required_role_policies          what the instance role needs, for a role a
#                                   central team creates
#
# None of them holds a secret. With tool_response_token_secret the runner reads
# its callback key from Secrets Manager at each start; the key is not in state.

locals {
  # The ports the runner dials on the Temporal address: Temporal, and the
  # tool-result listener when it is on the same host.
  temporal_ports = distinct(compact([
    local.temporal_port,
    local.tool_response_host == local.temporal_host ? local.tool_response_port : "",
  ]))

  temporal_purpose = local.tool_response_host == local.temporal_host ? "Temporal and sandbox tool results" : "Temporal"

  subnets_text = "The runner subnets (${join(", ", local.subnet_cidrs)})"

  # What the instances call besides Temporal and the tool-result listener.
  outbound_targets = concat(
    ["the image registry (${split("/", local.runner_image)[0]})"],
    var.ssm_enabled ? ["SSM Session Manager (the ssm, ssmmessages and ec2messages endpoints of ${var.region})"] : [],
    var.tool_response_token_secret != null ? ["Secrets Manager (the secretsmanager endpoint of ${split(":", var.tool_response_token_secret.arn)[3]}), for the callback key"] : [],
    ["the git hosts and the endpoints the tools call"],
  )

  network_owner_actions = concat(
    [
      "${local.subnets_text} need a route to ${local.temporal_host} and must be let in there on TCP ${join(" and ", local.temporal_ports)} (${local.temporal_purpose}). The runner load balancer of compositions/aws lets in its VPC by default; from another network, or to let in only the runner, set its runner_lb_allowed_cidr_blocks or runner_lb_allowed_security_group_ids.",
    ],
    local.tool_response_host != "" && local.tool_response_host != local.temporal_host ? [
      "${local.subnets_text} need a route to ${local.tool_response_host} and must be let in there on TCP ${local.tool_response_port} (sandbox tool results).",
    ] : [],
    [
      "${local.subnets_text} need outbound access${var.http_proxy != "" ? " through ${var.http_proxy}" : ""} to ${join(", ", local.outbound_targets)}. The instances get no public address.",
    ],
    var.existing_security_group_id != "" ? [
      "The security group ${var.existing_security_group_id} is brought, so we add no rule to it: let it out to ${local.temporal_host} on TCP ${join(" and ", local.temporal_ports)}${var.http_proxy != "" ? " and to the proxy" : ""}, and to the targets above on TCP 443.${var.key_name != "" ? " For SSH, let your jump hosts in on TCP 22." : ""}",
    ] : [],
  )
}

output "autoscaling_group_name" {
  description = "Name of the runner Auto Scaling group."
  value       = module.runner.autoscaling_group_name
}

output "launch_template_id" {
  description = "ID of the runner launch template."
  value       = module.runner.launch_template_id
}

output "ami_id" {
  description = "AMI the runner instances run: ami_id, the newest ami_name_filter match, or the latest Amazon Linux 2023."
  value       = module.runner.ami_id
}

output "security_group_id" {
  description = "ID of the runner instances' security group: ours, or existing_security_group_id."
  value       = module.runner.security_group_id
}

output "instance_profile_arn" {
  description = "ARN of the runner instances' instance profile: ours, or existing_instance_profile_arn."
  value       = module.runner.instance_profile_arn
}

output "iam_role_arn" {
  description = "ARN of the instance role we create. Empty with existing_instance_profile_arn."
  value       = module.runner.iam_role_arn
}

output "subnet_cidrs" {
  description = "Address ranges of subnet_ids, the source of the network rules."
  value       = local.subnet_cidrs
}

output "required_network_owner_actions" {
  description = "What the network owner must do, as readable lines: give the runner subnets a route to temporal_address (and tool_response_url) and allow them there, and give them outbound access to the registry and what the sandboxes call. With existing_security_group_id, also the rules the brought group needs."
  value       = local.network_owner_actions
}

output "required_role_policies" {
  description = "What the instance role needs, for accounts where a central team creates it (existing_instance_profile_arn): trust_policy (JSON), inline_policies (name => JSON: ecr-pull pulls from ecr_registry_host) and managed_policy_arns (name => ARN: ssm with ssm_enabled). Always filled; we attach them to our own role."
  value       = module.runner.required_role_policies
}
