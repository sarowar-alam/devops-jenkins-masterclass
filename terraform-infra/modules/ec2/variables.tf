variable "public_subnet_id" {
  description = "ID of the public subnet — masters land here"
  type        = string
}

variable "private_subnet_id" {
  description = "ID of the private subnet — agents land here"
  type        = string
}

variable "master_sg_id" {
  description = "Security group ID for master instances"
  type        = string
}

variable "agent_sg_id" {
  description = "Security group ID for agent instances"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name to attach to all instances (SSM access)"
  type        = string
}

variable "key_pair_name" {
  description = "Name of the existing AWS EC2 Key Pair"
  type        = string
}

variable "master_linux_instance_type" {
  description = "Instance type for Linux master"
  type        = string
}

variable "master_windows_instance_type" {
  description = "Instance type for Windows master"
  type        = string
}

variable "agent_linux_instance_type" {
  description = "Instance type for Linux agent"
  type        = string
}

variable "agent_windows_instance_type" {
  description = "Instance type for Windows agent"
  type        = string
}

variable "linux_root_volume_size" {
  description = "Root volume size (GB) for Linux instances"
  type        = number
}

variable "windows_root_volume_size" {
  description = "Root volume size (GB) for Windows instances"
  type        = number
}

variable "project_name" {
  description = "Project name — passed into user data templates as a template variable"
  type        = string
}

variable "environment" {
  description = "Environment label — passed into user data templates as a template variable"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource name tags"
  type        = string
}
