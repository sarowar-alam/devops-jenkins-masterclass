# ============================================================
# Root Module — BMI Infra
#
# Calls four child modules:
#   vpc      — VPC, subnets, IGW, NAT GW, route tables
#   security — Security Group (no inbound SSH)
#   iam      — IAM role + instance profile for SSM
#   ec2      — Ubuntu 24.04 EC2 in private subnet
#
# Authentication:
#   Uses the IAM role attached to the Jenkins EC2 server.
#   No static access keys — Terraform reads credentials from
#   the EC2 instance metadata service (IMDS) automatically.
# ============================================================

# ── Provider ─────────────────────────────────────────────────
# No access_key / secret_key.
# The Jenkins controller must have an IAM role attached with
# the permissions described in docs/07-terraform-pipeline.md.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Pipeline    = "Jenkins"
    }
  }
}

# ── Locals ────────────────────────────────────────────────────

locals {
  az          = "${var.aws_region}${var.availability_zone_suffix}"
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── Module: VPC ───────────────────────────────────────────────

module "vpc" {
  source = "./modules/vpc"

  name_prefix         = local.name_prefix
  availability_zone   = local.az
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
}

# ── Module: Security Group ────────────────────────────────────

module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
}

# ── Module: IAM (SSM role + instance profile) ─────────────────

module "iam" {
  source = "./modules/iam"

  name_prefix = local.name_prefix
}

# ── Module: EC2 ───────────────────────────────────────────────

module "ec2" {
  source = "./modules/ec2"

  name_prefix           = local.name_prefix
  project_name          = var.project_name
  environment           = var.environment
  subnet_id             = module.vpc.private_subnet_id
  security_group_ids    = [module.security.security_group_id]
  instance_profile_name = module.iam.instance_profile_name
  instance_type         = var.instance_type
  root_volume_size      = var.root_volume_size
}
