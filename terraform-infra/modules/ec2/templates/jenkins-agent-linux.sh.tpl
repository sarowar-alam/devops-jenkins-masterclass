#!/bin/bash
# jenkins-agent-linux.sh.tpl
# Terraform vars: ${project_name}, ${environment}
# All other shell vars use $VAR syntax (no braces) to avoid Terraform interpolation.
set -e
exec > /var/log/user-data.log 2>&1

echo "==================================================================="
echo " Jenkins Agent Linux Bootstrap"
echo " Project: ${project_name} | Environment: ${environment}"
echo " Started: $(date)"
echo "==================================================================="

# ── 1. System update ─────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  fontconfig \
  curl \
  gnupg2 \
  ca-certificates \
  apt-transport-https \
  software-properties-common \
  unzip \
  git

# ── 2. Java 17 (required for Jenkins agent JAR) ───────────────────────────────
apt-get install -y openjdk-17-jre
java -version

# ── 3. Docker CE ──────────────────────────────────────────────────────────────
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# ── 4. Add ubuntu user to docker group ───────────────────────────────────────
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# ── 5. AWS CLI v2 ─────────────────────────────────────────────────────────────
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# ── 6. Jenkins agent workspace directory ─────────────────────────────────────
mkdir -p /opt/jenkins-agent
chown ubuntu:ubuntu /opt/jenkins-agent

echo "==================================================================="
echo " Jenkins Agent Linux — Prerequisites Ready"
echo ""
echo " Connect this node in Jenkins UI:"
echo "   Host  : $(hostname -I | awk '{print $1}')"
echo "   Label : linux-agent"
echo "   Root  : /opt/jenkins-agent"
echo "   Launch: SSH | User: ubuntu"
echo "   Creds : Private key (sarowar-ostad-mumbai)"
echo ""
echo " SSM access: aws ssm start-session --target <instance-id>"
echo "==================================================================="
echo "Bootstrap complete: $(date)"
