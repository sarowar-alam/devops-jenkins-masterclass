# ============================================================
# Module: vpc
# Creates the full network layer for 1 Availability Zone:
#   VPC, Internet Gateway, public subnet, private subnet,
#   Elastic IP, NAT Gateway, public + private route tables
# ============================================================

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true  # Required: instances must resolve AWS endpoints (SSM)
  enable_dns_hostnames = true  # Required: instances need hostname resolution

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

# ── Public Subnet ─────────────────────────────────────────────
# Hosts the NAT Gateway. Instances here receive a public IP.

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-subnet"
    Tier = "public"
  }
}

# ── Private Subnet ────────────────────────────────────────────
# Hosts the application EC2 instance.
# No direct internet access — outbound only via NAT Gateway.

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "${var.name_prefix}-private-subnet"
    Tier = "private"
  }
}

# ── Elastic IP for NAT Gateway ────────────────────────────────

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]
  tags       = { Name = "${var.name_prefix}-nat-eip" }
}

# ── NAT Gateway ───────────────────────────────────────────────
# Must live in the PUBLIC subnet so it can reach the IGW.

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.this]
  tags          = { Name = "${var.name_prefix}-nat-gw" }
}

# ── Route Tables ─────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
