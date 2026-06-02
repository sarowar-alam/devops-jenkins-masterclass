output "instance_profile_name" {
  description = "EC2 instance profile name — passed to aws_instance.iam_instance_profile"
  value       = aws_iam_instance_profile.ec2_ssm.name
}

output "role_arn" {
  description = "ARN of the IAM role attached to the EC2 instance"
  value       = aws_iam_role.ec2_ssm.arn
}

output "role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.ec2_ssm.name
}
