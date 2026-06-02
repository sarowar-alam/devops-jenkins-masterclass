variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — used for intra-VPC rules (JNLP, agent SSH)"
  type        = string
}

variable "admin_cidr" {
  description = "Admin IP in CIDR notation for SSH and RDP access"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}
