locals {
  az          = "${var.aws_region}${var.availability_zone_suffix}"
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── VPC ────────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = local.az
  name_prefix         = local.name_prefix
}

# ── Security Groups ────────────────────────────────────────────────────────────

module "security" {
  source = "./modules/security"

  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = module.vpc.vpc_cidr_block
  admin_cidr  = var.admin_cidr
  name_prefix = local.name_prefix
}

# ── IAM — SSM role attached to all 4 instances ────────────────────────────────

module "iam" {
  source = "./modules/iam"

  name_prefix = local.name_prefix
}

# ── EC2 Instances ──────────────────────────────────────────────────────────────

module "ec2" {
  source = "./modules/ec2"

  public_subnet_id      = module.vpc.public_subnet_id
  private_subnet_id     = module.vpc.private_subnet_id
  master_sg_id          = module.security.master_sg_id
  agent_sg_id           = module.security.agent_sg_id
  instance_profile_name = module.iam.instance_profile_name
  key_pair_name         = var.key_pair_name

  master_linux_instance_type   = var.master_linux_instance_type
  master_windows_instance_type = var.master_windows_instance_type
  agent_linux_instance_type    = var.agent_linux_instance_type
  agent_windows_instance_type  = var.agent_windows_instance_type

  linux_root_volume_size   = var.linux_root_volume_size
  windows_root_volume_size = var.windows_root_volume_size

  project_name = var.project_name
  environment  = var.environment
  name_prefix  = local.name_prefix
}
