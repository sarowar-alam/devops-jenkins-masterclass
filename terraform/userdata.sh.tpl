#!/bin/bash
# ============================================================
# EC2 User Data — Runs ONCE on first boot
# Project: ${project_name} | Environment: ${environment}
# ============================================================

set -e
exec > /var/log/user-data.log 2>&1

echo "[$(date)] Starting user data bootstrap..."

# Wait for network to be fully available
sleep 10

# Update package index
apt-get update -y

# Install / upgrade SSM agent
# Ubuntu 24.04 AMIs from Canonical typically ship with SSM agent.
# This ensures it is the latest version and is enabled on boot.
apt-get install -y amazon-ssm-agent

systemctl enable amazon-ssm-agent
systemctl start  amazon-ssm-agent

echo "[$(date)] SSM agent status:"
systemctl status amazon-ssm-agent --no-pager

echo "[$(date)] User data bootstrap complete."
echo "[$(date)] Connect via: aws ssm start-session --target $(ec2metadata --instance-id 2>/dev/null || curl -s http://169.254.169.254/latest/meta-data/instance-id)"
