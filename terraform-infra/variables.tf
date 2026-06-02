# ── Authentication ─────────────────────────────────────────────────────────────

variable "aws_profile" {
  description = "AWS named profile to use for authentication (~/.aws/config)"
  type        = string
  default     = "sarowar-ostad"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

# ── Placement ──────────────────────────────────────────────────────────────────

variable "availability_zone_suffix" {
  description = "Single AZ suffix — all resources land in one AZ (a, b, or c)"
  type        = string
  default     = "a"
}

variable "project_name" {
  description = "Project name used as a prefix in all resource names"
  type        = string
  default     = "jenkins-infra"
}

variable "environment" {
  description = "Deployment environment label (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# ── Networking ─────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (masters)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (agents)"
  type        = string
  default     = "10.0.2.0/24"
}

# ── Security ───────────────────────────────────────────────────────────────────

variable "admin_cidr" {
  description = "Your IP in CIDR notation for SSH and RDP access — e.g. 203.0.113.10/32 (find it: curl -s ifconfig.me)"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_cidr))
    error_message = "admin_cidr must be a valid CIDR block, e.g. 203.0.113.10/32."
  }
}

# ── Key Pair ───────────────────────────────────────────────────────────────────

variable "key_pair_name" {
  description = "Name of an existing AWS EC2 Key Pair to attach to all instances"
  type        = string
  default     = "sarowar-ostad-mumbai"
}

# ── Instance Types ─────────────────────────────────────────────────────────────

variable "master_linux_instance_type" {
  description = "Instance type for Jenkins Linux master (Ubuntu 24.04)"
  type        = string
  default     = "t3.medium"
}

variable "master_windows_instance_type" {
  description = "Instance type for Jenkins Windows master (Windows Server 2019) — t3.large gives 8 GB RAM needed by Jenkins on Windows"
  type        = string
  default     = "t3.large"
}

variable "agent_linux_instance_type" {
  description = "Instance type for Jenkins Linux agent"
  type        = string
  default     = "t3.small"
}

variable "agent_windows_instance_type" {
  description = "Instance type for Jenkins Windows agent"
  type        = string
  default     = "t3.medium"
}

# ── Storage ────────────────────────────────────────────────────────────────────

variable "linux_root_volume_size" {
  description = "Root EBS volume size in GB for Linux instances"
  type        = number
  default     = 30
}

variable "windows_root_volume_size" {
  description = "Root EBS volume size in GB for Windows instances — 50 GB covers OS baseline + Jenkins workspace"
  type        = number
  default     = 50
}
