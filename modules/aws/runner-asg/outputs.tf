output "autoscaling_group_name" {
  description = "Name of the runner Auto Scaling group."
  value       = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  description = "ID of the runner launch template."
  value       = aws_launch_template.this.id
}

output "security_group_id" {
  description = "ID of the runner security group, e.g. for the NLB's allowed_security_group_ids."
  value       = aws_security_group.this.id
}

output "iam_role_arn" {
  description = "ARN of the runner instance role."
  value       = aws_iam_role.this.arn
}

output "iam_role_name" {
  description = "Name of the runner instance role, for attaching more policies outside the module."
  value       = aws_iam_role.this.name
}
