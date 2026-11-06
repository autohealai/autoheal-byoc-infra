output "autoscaling_group_name" {
  description = "Name of the runner Auto Scaling group."
  value       = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  description = "ID of the runner launch template."
  value       = aws_launch_template.this.id
}

output "ami_id" {
  description = "AMI the launch template uses: ami_id, the newest ami_name_filter match, or the latest Amazon Linux 2023."
  value       = local.ami_id
}

output "security_group_id" {
  description = "ID of the instances' security group: the module's, or existing_security_group_id."
  value       = local.security_group_id
}

output "instance_profile_arn" {
  description = "ARN of the instance profile the instances use: the module's, or existing_instance_profile_arn."
  value       = local.create_role ? aws_iam_instance_profile.this[0].arn : var.existing_instance_profile_arn
}

output "iam_role_arn" {
  description = "ARN of the instance role the module creates. Empty with existing_instance_profile_arn."
  value       = local.create_role ? aws_iam_role.this[0].arn : ""
}

output "iam_role_name" {
  description = "Name of the instance role the module creates, for attaching more policies outside the module. Empty with existing_instance_profile_arn."
  value       = local.create_role ? aws_iam_role.this[0].name : ""
}

output "required_role_policies" {
  description = "What the instance role needs: trust_policy (JSON), inline_policies (name => JSON; ecr-pull pulls from ecr_registry_host, then additional_inline_policies) and managed_policy_arns (name => ARN). The module attaches them to its own role; with existing_instance_profile_arn the role's owner attaches them."
  value = {
    trust_policy        = local.ec2_trust_policy
    inline_policies     = local.inline_policies
    managed_policy_arns = local.managed_policy_arns
  }
}
