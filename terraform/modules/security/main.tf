# ============================================================
# Module: security
# Creates the EC2 Security Group.
#
# Design:
#   Inbound  → NONE (private subnet, no public IP, no SSH)
#   Outbound → HTTPS 443 (SSM agent, AWS APIs)
#              HTTP  80  (apt-get package downloads)
# ============================================================

resource "aws_security_group" "ec2" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "Private EC2: no inbound SSH — outbound HTTPS/HTTP for SSM and packages"
  vpc_id      = var.vpc_id

  # HTTPS — SSM agent registration, AWS service calls, ECR/S3 access
  egress {
    description = "HTTPS — SSM agent, AWS APIs, package registry"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP — Ubuntu apt package manager (mirrors use plain HTTP)
  egress {
    description = "HTTP — apt package manager"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-ec2-sg" }

  lifecycle {
    create_before_destroy = true
  }
}
