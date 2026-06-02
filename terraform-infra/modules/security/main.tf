# master-sg: Jenkins UI open to all, SSH/RDP locked to admin_cidr
resource "aws_security_group" "master" {
  name        = "${var.name_prefix}-master-sg"
  description = "Jenkins master - 8080 public, 50000 from VPC, SSH/RDP from admin"
  vpc_id      = var.vpc_id

  ingress {
    description = "Jenkins Web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Jenkins JNLP agent connections (from VPC)"
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "RDP from admin"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-master-sg"
  }
}

# agent-sg: SSH from VPC (master→agent), RDP from admin only
resource "aws_security_group" "agent" {
  name        = "${var.name_prefix}-agent-sg"
  description = "Jenkins agent - SSH from VPC, RDP from admin, no public inbound"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from Jenkins master (within VPC)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "RDP from admin (Windows agent)"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "All outbound traffic (NAT GW for package installs + SSM)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-agent-sg"
  }
}
