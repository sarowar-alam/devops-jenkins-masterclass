#!/bin/bash
# ============================================================
# EC2 User Data — Runs ONCE on first boot
# Project: ${project_name} | Environment: ${environment}
# ============================================================

set -e
exec > /var/log/user-data.log 2>&1

echo "[$(date)] Starting user data bootstrap..."

# Wait for network to stabilise after first boot
sleep 10

# Update package index
apt-get update -y

# Install / upgrade SSM agent
# Ubuntu 24.04 AMIs from Canonical typically ship with SSM agent pre-installed.
# This step ensures it is the latest version and enabled on boot.
apt-get install -y amazon-ssm-agent

systemctl enable amazon-ssm-agent
systemctl start  amazon-ssm-agent

echo "[$(date)] SSM agent status:"
systemctl status amazon-ssm-agent --no-pager

INSTANCE_ID=$(curl -s -m 5 http://169.254.169.254/latest/meta-data/instance-id || echo "unknown")
echo "[$(date)] Bootstrap complete. Instance ID: ${INSTANCE_ID}"
