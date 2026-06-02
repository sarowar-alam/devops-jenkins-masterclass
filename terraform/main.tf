# ============================================================
# BMI Infra — Main Terraform Configuration
#
# Infrastructure Created:
#   VPC (1 AZ)
#   ├── Public Subnet  → Internet Gateway → 0.0.0.0/0
#   ├── Private Subnet → NAT Gateway → Internet (for SSM)
#   ├── Elastic IP     → attached to NAT Gateway
#   ├── Security Group → EC2 (no inbound, HTTPS/HTTP outbound)
#   └── EC2 (private subnet)
#       ├── Ubuntu 24.04 LTS (latest AMI from Canonical)
#       ├── IAM Instance Profile → AmazonSSMManagedInstanceCore
#       ├── No SSH key pair (access via SSM Session Manager only)
#       └── Encrypted gp3 root volume
# ============================================================

# ── Provider ─────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# ── Locals ────────────────────────────────────────────────────

locals {
  az = "${var.aws_region}${var.availability_zone_suffix}"

  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Pipeline    = "Jenkins"
    CreatedAt   = timestamp()
  }
}

# ── AMI Data Source ────────────────────────────────────────────
# Always resolves to the latest Ubuntu 24.04 LTS AMI from Canonical.
# Canonical's official AWS account ID is 099720109477.
# The AMI name pattern uses 'noble' which is Ubuntu 24.04's codename.

data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu's publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ── VPC ───────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true  # Required for SSM — instances must resolve AWS endpoints
  enable_dns_hostnames = true  # Required for SSM — instances need DNS hostnames

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# ── Internet Gateway ──────────────────────────────────────────
# Attached to the VPC to provide the public subnet with internet access.
# Also required for the NAT Gateway to route outbound traffic.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ── Public Subnet ─────────────────────────────────────────────
# Hosts the NAT Gateway. EC2 instances in this subnet get public IPs.
# No application workloads are placed here in this architecture.

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet"
    Tier = "public"
  }
}

# ── Private Subnet ────────────────────────────────────────────
# Hosts the application EC2 instance.
# No direct internet access — outbound only via NAT Gateway.
# No SSH inbound — instances accessed via SSM Session Manager.

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.az

  tags = {
    Name = "${local.name_prefix}-private-subnet"
    Tier = "private"
  }
}

# ── Elastic IP for NAT Gateway ────────────────────────────────
# Static public IP address allocated to the NAT Gateway.
# All outbound internet traffic from the private subnet appears
# to come from this IP address.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }

  # EIP must be created after IGW is attached to avoid dependency issues
  depends_on = [aws_internet_gateway.main]
}

# ── NAT Gateway ───────────────────────────────────────────────
# Placed in the PUBLIC subnet (this is required — NAT Gateways must
# be in a public subnet to route traffic to the internet gateway).
#
# The PRIVATE subnet's route table points default route → this NAT GW.
# This allows the private EC2 instance to:
#   - Call SSM endpoints (required for SSM agent registration)
#   - Run apt-get update / install packages
#   - Pull from ECR, S3, or any AWS service endpoint

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id  # NAT GW lives in PUBLIC subnet

  tags = {
    Name = "${local.name_prefix}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

# ── Public Route Table ────────────────────────────────────────
# Routes all internet-bound traffic from the public subnet → IGW

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Table ───────────────────────────────────────
# Routes all internet-bound traffic from the private subnet → NAT GW

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ── Security Group ────────────────────────────────────────────
# Applied to the private EC2 instance.
#
# INBOUND: No rules — the instance is in a private subnet with no
#   public IP. SSH is intentionally disabled. Access is only via
#   SSM Session Manager (which uses the IAM role, not network ports).
#
# OUTBOUND: HTTPS (443) and HTTP (80) to allow:
#   - SSM agent to register and maintain connection to AWS endpoints
#   - apt-get to download packages
#   - Any AWS service API calls (ECR, S3, CloudWatch, etc.)

resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Private EC2: no inbound SSH, outbound HTTPS/HTTP for SSM + packages"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS — SSM agent, AWS APIs, package registry"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP — apt package manager"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ec2-sg"
  }
}

# ── IAM Role for SSM ──────────────────────────────────────────
# This IAM role is what allows SSM Session Manager to connect to the
# EC2 instance WITHOUT an SSH key or open port 22.
#
# How SSM works:
#   1. EC2 boots with this IAM role attached
#   2. SSM agent (pre-installed on Ubuntu 24.04 AMIs) calls AWS SSM APIs
#   3. SSM registers the instance using the IAM role credentials
#   4. You connect via AWS Console → Systems Manager → Session Manager
#      or: aws ssm start-session --target <instance-id>
#   5. The session is encrypted end-to-end over HTTPS (port 443)
#      — no port 22 needed, no key pair needed

resource "aws_iam_role" "ec2_ssm" {
  name        = "${local.name_prefix}-ec2-ssm-role"
  description = "Allows EC2 instances to register with SSM and be managed via Session Manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Sid       = "AllowEC2ToAssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-ec2-ssm-role"
  }
}

# Attach the AWS-managed policy that grants all SSM Session Manager permissions
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile — the wrapper that allows an IAM role to be attached to EC2
resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${local.name_prefix}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name

  tags = {
    Name = "${local.name_prefix}-ec2-ssm-profile"
  }
}

# ── EC2 Instance ──────────────────────────────────────────────

resource "aws_instance" "private" {
  ami           = data.aws_ami.ubuntu_24_04.id
  instance_type = var.instance_type

  # Place in private subnet — no public IP
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false

  # Attach the security group
  vpc_security_group_ids = [aws_security_group.ec2.id]

  # Attach the SSM instance profile — this is what enables SSM access
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name

  # No key_name — access is exclusively via SSM Session Manager

  # Encrypted gp3 root volume
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${local.name_prefix}-root-volume"
    }
  }

  # User data script — runs once on first boot
  # Ubuntu 24.04 AMIs typically have SSM agent pre-installed.
  # This script ensures it is running and enabled on boot.
  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    project_name = var.project_name
    environment  = var.environment
  }))

  tags = {
    Name = "${local.name_prefix}-private-ec2"
  }

  # Lifecycle: prevent accidental destroy when running terraform apply on updates
  lifecycle {
    create_before_destroy = false
  }
}
