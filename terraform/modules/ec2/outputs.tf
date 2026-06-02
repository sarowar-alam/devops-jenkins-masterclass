output "instance_id" {
  description = "EC2 instance ID — use this to start an SSM session"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.this.private_ip
}

output "ami_id" {
  description = "Ubuntu 24.04 AMI ID used to launch the instance"
  value       = data.aws_ami.ubuntu_24_04.id
}

output "ami_name" {
  description = "Ubuntu 24.04 AMI name"
  value       = data.aws_ami.ubuntu_24_04.name
}
