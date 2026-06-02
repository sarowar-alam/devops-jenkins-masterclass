# ── Linux Master ───────────────────────────────────────────────────────────────

output "master_linux_instance_id" {
  description = "Instance ID of Jenkins Linux master"
  value       = module.ec2.master_linux_instance_id
}

output "master_linux_public_ip" {
  description = "Public IP of Jenkins Linux master"
  value       = module.ec2.master_linux_public_ip
}

output "master_linux_jenkins_url" {
  description = "Jenkins UI URL for Linux master (wait ~3 min after apply)"
  value       = "http://${module.ec2.master_linux_public_ip}:8080"
}

output "master_linux_ssh_command" {
  description = "SSH command to connect to Linux master"
  value       = "ssh -i ~/.ssh/sarowar-ostad-mumbai.pem ubuntu@${module.ec2.master_linux_public_ip}"
}

output "master_linux_get_password" {
  description = "Command to retrieve Jenkins initial admin password from Linux master"
  value       = "ssh -i ~/.ssh/sarowar-ostad-mumbai.pem ubuntu@${module.ec2.master_linux_public_ip} 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'"
}

# ── Windows Master ─────────────────────────────────────────────────────────────

output "master_windows_instance_id" {
  description = "Instance ID of Jenkins Windows master"
  value       = module.ec2.master_windows_instance_id
}

output "master_windows_public_ip" {
  description = "Public IP of Jenkins Windows master"
  value       = module.ec2.master_windows_public_ip
}

output "master_windows_jenkins_url" {
  description = "Jenkins UI URL for Windows master (wait ~5 min after apply)"
  value       = "http://${module.ec2.master_windows_public_ip}:8080"
}

output "master_windows_rdp" {
  description = "RDP connection string for Windows master"
  value       = "${module.ec2.master_windows_public_ip}:3389"
}

output "master_windows_get_password" {
  description = "AWS CLI command to decrypt Windows administrator password"
  value       = "aws ec2 get-password-data --instance-id ${module.ec2.master_windows_instance_id} --priv-launch-key ~/.ssh/sarowar-ostad-mumbai.pem --profile sarowar-ostad --region ap-south-1"
}

# ── Linux Agent ────────────────────────────────────────────────────────────────

output "agent_linux_instance_id" {
  description = "Instance ID of Jenkins Linux agent"
  value       = module.ec2.agent_linux_instance_id
}

output "agent_linux_private_ip" {
  description = "Private IP of Jenkins Linux agent"
  value       = module.ec2.agent_linux_private_ip
}

output "agent_linux_ssm_connect" {
  description = "SSM Session Manager command to connect to Linux agent"
  value       = "aws ssm start-session --target ${module.ec2.agent_linux_instance_id} --profile sarowar-ostad --region ap-south-1"
}

# ── Windows Agent ──────────────────────────────────────────────────────────────

output "agent_windows_instance_id" {
  description = "Instance ID of Jenkins Windows agent"
  value       = module.ec2.agent_windows_instance_id
}

output "agent_windows_private_ip" {
  description = "Private IP of Jenkins Windows agent"
  value       = module.ec2.agent_windows_private_ip
}

output "agent_windows_ssm_connect" {
  description = "SSM Session Manager command to connect to Windows agent"
  value       = "aws ssm start-session --target ${module.ec2.agent_windows_instance_id} --profile sarowar-ostad --region ap-south-1"
}

# ── Summary ────────────────────────────────────────────────────────────────────

output "next_steps" {
  description = "What to do after terraform apply completes"
  value       = <<-EOT

    ============================================================
    JENKINS INFRASTRUCTURE DEPLOYED — NEXT STEPS
    ============================================================

    Wait 3-5 minutes for user data to finish on all instances.

    1. LINUX MASTER  →  ${module.ec2.master_linux_public_ip}
       Browser  : http://${module.ec2.master_linux_public_ip}:8080
       SSH      : ssh -i ~/.ssh/sarowar-ostad-mumbai.pem ubuntu@${module.ec2.master_linux_public_ip}
       Password : ssh -i ~/.ssh/sarowar-ostad-mumbai.pem ubuntu@${module.ec2.master_linux_public_ip} \
                    'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'
       Log      : ssh then: sudo tail -f /var/log/user-data.log

    2. WINDOWS MASTER  →  ${module.ec2.master_windows_public_ip}
       Browser  : http://${module.ec2.master_windows_public_ip}:8080
       RDP      : ${module.ec2.master_windows_public_ip}:3389  (user: Administrator)
       Password : aws ec2 get-password-data \
                    --instance-id ${module.ec2.master_windows_instance_id} \
                    --priv-launch-key ~/.ssh/sarowar-ostad-mumbai.pem \
                    --profile sarowar-ostad --region ap-south-1
       Log      : RDP then: Get-Content C:\jenkins-bootstrap.log

    3. LINUX AGENT  (private subnet — ${module.ec2.agent_linux_private_ip})
       SSM      : aws ssm start-session --target ${module.ec2.agent_linux_instance_id} \
                    --profile sarowar-ostad --region ap-south-1
       Add in Jenkins UI: SSH agent | Host: ${module.ec2.agent_linux_private_ip}
       Label: linux-agent | Root: /opt/jenkins-agent | User: ubuntu

    4. WINDOWS AGENT  (private subnet — ${module.ec2.agent_windows_private_ip})
       SSM      : aws ssm start-session --target ${module.ec2.agent_windows_instance_id} \
                    --profile sarowar-ostad --region ap-south-1
       Add in Jenkins UI: JNLP agent
       Label: windows-agent | Root: C:\jenkins-agent

    5. Run SL#2-6 Jenkinsfiles once agents are connected to both masters.

    ============================================================
    DESTROY: terraform destroy -var="admin_cidr=YOUR_IP/32"
    ============================================================
  EOT
}
