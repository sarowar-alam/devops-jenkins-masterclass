# ============================================================
# Outputs — Displayed in Jenkins console after 'terraform apply'
# Captured by pipeline and written to terraform-outputs.txt
# ============================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "availability_zone" {
  description = "Availability zone all resources were deployed into"
  value       = local.az
}

output "public_subnet_id" {
  description = "Public subnet ID (hosts the NAT Gateway)"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID (hosts the EC2 instance)"
  value       = aws_subnet.private.id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway — all outbound traffic from the private subnet appears from this IP"
  value       = aws_eip.nat.public_ip
}

output "security_group_id" {
  description = "Security Group ID attached to the EC2 instance"
  value       = aws_security_group.ec2.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the EC2 instance for SSM access"
  value       = aws_iam_role.ec2_ssm.arn
}

output "ec2_instance_id" {
  description = "EC2 instance ID — use this to start an SSM session"
  value       = aws_instance.private.id
}

output "ec2_private_ip" {
  description = "Private IP address of the EC2 instance (not reachable from internet)"
  value       = aws_instance.private.private_ip
}

output "ec2_ami_id" {
  description = "Ubuntu 24.04 AMI ID that was used to launch the instance"
  value       = data.aws_ami.ubuntu_24_04.id
}

output "ec2_ami_name" {
  description = "Ubuntu 24.04 AMI name"
  value       = data.aws_ami.ubuntu_24_04.name
}

output "ssm_connect_command" {
  description = "AWS CLI command to open an interactive shell session on the EC2 instance — no SSH key or port 22 needed"
  value       = "aws ssm start-session --target ${aws_instance.private.id} --region ${var.aws_region}"
}

output "ssm_connect_console_url" {
  description = "AWS Console URL to connect via SSM Session Manager (replace REGION and INSTANCE_ID)"
  value       = "https://${var.aws_region}.console.aws.amazon.com/systems-manager/session-manager/${aws_instance.private.id}"
}
