output "master_linux_instance_id" {
  description = "Instance ID of Jenkins Linux master"
  value       = aws_instance.master_linux.id
}

output "master_linux_public_ip" {
  description = "Public IP of Jenkins Linux master"
  value       = aws_instance.master_linux.public_ip
}

output "master_windows_instance_id" {
  description = "Instance ID of Jenkins Windows master"
  value       = aws_instance.master_windows.id
}

output "master_windows_public_ip" {
  description = "Public IP of Jenkins Windows master"
  value       = aws_instance.master_windows.public_ip
}

output "agent_linux_instance_id" {
  description = "Instance ID of Jenkins Linux agent"
  value       = aws_instance.agent_linux.id
}

output "agent_linux_private_ip" {
  description = "Private IP of Jenkins Linux agent"
  value       = aws_instance.agent_linux.private_ip
}

output "agent_windows_instance_id" {
  description = "Instance ID of Jenkins Windows agent"
  value       = aws_instance.agent_windows.id
}

output "agent_windows_private_ip" {
  description = "Private IP of Jenkins Windows agent"
  value       = aws_instance.agent_windows.private_ip
}
