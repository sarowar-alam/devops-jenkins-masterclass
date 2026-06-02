variable "vpc_id" {
  description = "VPC ID to create the security group in."
  type        = string
}

variable "name_prefix" {
  description = "Short prefix used in resource Name tags. Format: <project>-<environment>."
  type        = string
}
