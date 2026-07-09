#!/bin/bash
# jenkins-master-linux.sh.tpl
# Terraform vars: ${project_name}, ${environment}
# All other shell vars use $VAR syntax (no braces) to avoid Terraform interpolation.
set -e
exec > /var/log/user-data.log 2>&1

echo "==================================================================="
echo " Jenkins Master Linux Bootstrap"
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

# ── 2. Java 21 (required by Jenkins LTS 2.492+) ──────────────────────────────
apt-get install -y openjdk-21-jre
java -version

# ── 3. Jenkins LTS repository ────────────────────────────────────────────────
# Jenkins rotated signing key Dec 2025 — use jenkins.io-2026.key.
# Save ASCII-armored to /etc/apt/keyrings/ (no gpg --dearmor needed).
install -m 0755 -d /etc/apt/keyrings
wget -q -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

# ── 4. Enable and start Jenkins ───────────────────────────────────────────────
systemctl enable jenkins
systemctl start jenkins

# ── 5. AWS CLI v2 ─────────────────────────────────────────────────────────────
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws
# Ensure jenkins (non-login) user can traverse the AWS CLI v2 directory
chmod -R a+rx /usr/local/aws-cli/

# ── 6. UFW firewall ───────────────────────────────────────────────────────────
ufw allow 22/tcp
ufw allow 8080/tcp
ufw allow 50000/tcp
ufw --force enable

# ── 7. Wait for initialAdminPassword ─────────────────────────────────────────
echo "--- Waiting for Jenkins initialAdminPassword ---"
maxWait=300
elapsed=0
passFile=/var/lib/jenkins/secrets/initialAdminPassword

while [ ! -f $passFile ]; do
  if [ $elapsed -ge $maxWait ]; then
    echo "ERROR: Jenkins did not write initialAdminPassword within $maxWait seconds"
    echo "Check: sudo systemctl status jenkins"
    break
  fi
  sleep 5
  elapsed=$((elapsed + 5))
  echo "Waiting... ($elapsed/$maxWait seconds)"
done

if [ -f $passFile ]; then
  echo "==================================================================="
  echo " Jenkins Initial Admin Password:"
  cat $passFile
  echo "==================================================================="
fi

echo "Bootstrap complete: $(date)"
echo "Open: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
