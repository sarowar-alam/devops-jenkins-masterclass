output "instance_profile_name" {
  description = "EC2 instance profile name — attach to all Jenkins instances"
  value       = aws_iam_instance_profile.jenkins_ec2.name
}

output "role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.jenkins_ec2.arn
}

output "role_name" {
  description = "IAM role name"
  value       = aws_iam_role.jenkins_ec2.name
}
