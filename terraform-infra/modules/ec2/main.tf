# ── AMI Data Sources ───────────────────────────────────────────────────────────

data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

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

data "aws_ami" "windows_2019" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Jenkins Master — Linux ─────────────────────────────────────────────────────

resource "aws_instance" "master_linux" {
  ami                         = data.aws_ami.ubuntu_24_04.id
  instance_type               = var.master_linux_instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.master_sg_id]
  iam_instance_profile        = var.instance_profile_name
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.linux_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/jenkins-master-linux.sh.tpl", {
    project_name = var.project_name
    environment  = var.environment
  })

  tags = {
    Name = "${var.name_prefix}-master-linux"
    Role = "jenkins-master"
    OS   = "ubuntu-24.04"
  }
}

# ── Jenkins Master — Windows ───────────────────────────────────────────────────

resource "aws_instance" "master_windows" {
  ami                         = data.aws_ami.windows_2019.id
  instance_type               = var.master_windows_instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.master_sg_id]
  iam_instance_profile        = var.instance_profile_name
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.windows_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/jenkins-master-windows.ps1.tpl", {
    project_name = var.project_name
    environment  = var.environment
  })

  tags = {
    Name = "${var.name_prefix}-master-windows"
    Role = "jenkins-master"
    OS   = "windows-2019"
  }
}

# ── Jenkins Agent — Linux ──────────────────────────────────────────────────────

resource "aws_instance" "agent_linux" {
  ami                         = data.aws_ami.ubuntu_24_04.id
  instance_type               = var.agent_linux_instance_type
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [var.agent_sg_id]
  iam_instance_profile        = var.instance_profile_name
  key_name                    = var.key_pair_name
  associate_public_ip_address = false

  root_block_device {
    volume_size           = var.linux_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/jenkins-agent-linux.sh.tpl", {
    project_name = var.project_name
    environment  = var.environment
  })

  tags = {
    Name = "${var.name_prefix}-agent-linux"
    Role = "jenkins-agent"
    OS   = "ubuntu-24.04"
  }
}

# ── Jenkins Agent — Windows ────────────────────────────────────────────────────

resource "aws_instance" "agent_windows" {
  ami                         = data.aws_ami.windows_2019.id
  instance_type               = var.agent_windows_instance_type
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [var.agent_sg_id]
  iam_instance_profile        = var.instance_profile_name
  key_name                    = var.key_pair_name
  associate_public_ip_address = false

  root_block_device {
    volume_size           = var.windows_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/jenkins-agent-windows.ps1.tpl", {
    project_name = var.project_name
    environment  = var.environment
  })

  tags = {
    Name = "${var.name_prefix}-agent-windows"
    Role = "jenkins-agent"
    OS   = "windows-2019"
  }
}
