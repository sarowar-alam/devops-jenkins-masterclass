# ============================================================
# Module: ec2
# Creates the EC2 instance in the private subnet.
# - Ubuntu 24.04 LTS (latest AMI from Canonical)
# - No key pair — accessed via SSM Session Manager only
# - Encrypted gp3 root volume
# - userdata.sh.tpl bootstraps the SSM agent on first boot
# ============================================================

# Always resolve the latest Ubuntu 24.04 LTS AMI from Canonical.
# Canonical's official AWS account ID: 099720109477
# 'noble' is the Ubuntu 24.04 LTS codename.
data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "this" {
  ami           = data.aws_ami.ubuntu_24_04.id
  instance_type = var.instance_type

  # Place in private subnet — no public IP assigned
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false

  vpc_security_group_ids = var.security_group_ids

  # SSM instance profile — enables Session Manager without port 22
  iam_instance_profile = var.instance_profile_name

  # No key_name — access is exclusively via SSM Session Manager

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
    tags                  = { Name = "${var.name_prefix}-root-volume" }
  }

  # User data: ensures SSM agent is installed and running on first boot
  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    project_name = var.project_name
    environment  = var.environment
  }))

  tags = { Name = "${var.name_prefix}-private-ec2" }
}
