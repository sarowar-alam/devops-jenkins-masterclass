variable "subnet_id" {
  description = "Private subnet ID to place the EC2 instance in."
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to the instance."
  type        = list(string)
}

variable "instance_profile_name" {
  description = "IAM instance profile name that grants SSM access."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 20
}

variable "name_prefix" {
  description = "Short prefix used in resource Name tags. Format: <project>-<environment>."
  type        = string
}

variable "project_name" {
  description = "Project name — injected into user data script."
  type        = string
}

variable "environment" {
  description = "Environment label — injected into user data script."
  type        = string
}
