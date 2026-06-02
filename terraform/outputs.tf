# ============================================================
# Root Outputs — sourced from child modules
# ============================================================

# ── VPC ───────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "availability_zone" {
  description = "Availability zone all resources were deployed into"
  value       = local.az
}

output "public_subnet_id" {
  description = "Public subnet ID (hosts the NAT Gateway)"
  value       = module.vpc.public_subnet_id
}

output "private_subnet_id" {
  description = "Private subnet ID (hosts the EC2 instance)"
  value       = module.vpc.private_subnet_id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = module.vpc.nat_gateway_id
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway"
  value       = module.vpc.nat_public_ip
}

# ── Security ──────────────────────────────────────────────────

output "security_group_id" {
  description = "Security Group ID attached to the EC2 instance"
  value       = module.security.security_group_id
}

# ── IAM ───────────────────────────────────────────────────────

output "iam_role_arn" {
  description = "ARN of the IAM role granting SSM access"
  value       = module.iam.role_arn
}

# ── EC2 ───────────────────────────────────────────────────────

output "ec2_instance_id" {
  description = "EC2 instance ID — use this to start an SSM session"
  value       = module.ec2.instance_id
}

output "ec2_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = module.ec2.private_ip
}

output "ec2_ami_id" {
  description = "Ubuntu 24.04 AMI ID used to launch the instance"
  value       = module.ec2.ami_id
}

output "ec2_ami_name" {
  description = "Ubuntu 24.04 AMI name"
  value       = module.ec2.ami_name
}

# ── SSM Connection ────────────────────────────────────────────

output "ssm_connect_command" {
  description = "AWS CLI command to open a shell on the EC2 instance — no SSH key needed"
  value       = "aws ssm start-session --target ${module.ec2.instance_id} --region ${var.aws_region}"
}

output "ssm_connect_console_url" {
  description = "AWS Console direct link for SSM Session Manager"
  value       = "https://${var.aws_region}.console.aws.amazon.com/systems-manager/session-manager/${module.ec2.instance_id}"
}
