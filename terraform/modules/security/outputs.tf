output "security_group_id" {
  description = "Security Group ID attached to the EC2 instance"
  value       = aws_security_group.ec2.id
}
