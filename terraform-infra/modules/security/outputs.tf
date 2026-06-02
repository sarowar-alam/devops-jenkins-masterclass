output "master_sg_id" {
  description = "Security group ID for Jenkins master instances"
  value       = aws_security_group.master.id
}

output "agent_sg_id" {
  description = "Security group ID for Jenkins agent instances"
  value       = aws_security_group.agent.id
}
