output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = aws_vpc.this.cidr_block
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
  value       = aws_nat_gateway.this.id
}

output "nat_public_ip" {
  description = "Public IP of the NAT Gateway (all private-subnet outbound traffic appears from this IP)"
  value       = aws_eip.nat.public_ip
}
