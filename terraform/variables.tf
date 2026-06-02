# ============================================================
# Root Variables — BMI Infra
# ============================================================

# ── AWS Region & Availability Zone ───────────────────────────

variable "aws_region" {
  description = "AWS region where all resources will be created."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region code, e.g. us-east-1."
  }
}

variable "availability_zone_suffix" {
  description = "Single AZ suffix (a, b, c). Combined with aws_region to form the full AZ name."
  type        = string
  default     = "a"

  validation {
    condition     = contains(["a", "b", "c", "d"], var.availability_zone_suffix)
    error_message = "Must be one of: a, b, c, d."
  }
}

# ── Project & Environment ─────────────────────────────────────

variable "project_name" {
  description = "Short name prefix applied to all resource names and tags."
  type        = string
  default     = "bmi-infra"
}

variable "environment" {
  description = "Deployment environment — used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be one of: dev, staging, prod."
  }
}

# ── Network ───────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet. Must be within vpc_cidr."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet. Must be within vpc_cidr."
  type        = string
  default     = "10.0.2.0/24"
}

# ── EC2 Instance ──────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type for the private server."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 500
    error_message = "root_volume_size must be between 8 and 500 GB."
  }
}
