variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet. Must be within vpc_cidr."
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet. Must be within vpc_cidr."
  type        = string
}

variable "availability_zone" {
  description = "Full AZ name, e.g. us-east-1a. All subnets are placed in this single AZ."
  type        = string
}

variable "name_prefix" {
  description = "Short prefix used in all resource Name tags. Format: <project>-<environment>."
  type        = string
}
