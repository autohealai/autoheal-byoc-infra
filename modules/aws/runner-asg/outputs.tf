output "asg_name" {
  description = "Name of the runner Auto Scaling Group."
  value       = aws_autoscaling_group.runner.name
}

output "launch_template_id" {
  description = "ID of the runner launch template."
  value       = aws_launch_template.runner.id
}

output "role_arn" {
  description = "IAM role ARN of the runner instance profile (granted ECR pull + SSM)."
  value       = aws_iam_role.runner.arn
}

output "security_group_id" {
  description = "Security group ID attached to the runner instances."
  value       = aws_security_group.runner.id
}
