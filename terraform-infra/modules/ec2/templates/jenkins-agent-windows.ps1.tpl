<powershell>
# jenkins-agent-windows.ps1.tpl
# Terraform vars: ${project_name}, ${environment}
# All PowerShell vars use $var syntax (no braces) to avoid Terraform interpolation.

Start-Transcript -Path "C:\jenkins-agent-bootstrap.log" -Force

Write-Host "==================================================================="
Write-Host " Jenkins Agent Windows Bootstrap"
Write-Host " Project: ${project_name} | Environment: ${environment}"
Write-Host " Started: $(Get-Date)"
Write-Host "==================================================================="

# ── 1. Install Chocolatey ────────────────────────────────────────────────────
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = `
  [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
  'https://community.chocolatey.org/install.ps1'
))

# Refresh PATH after Chocolatey install
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + `
            [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "--- Chocolatey installed ---"

# ── 2. Install Java 17, Git, NSSM ────────────────────────────────────────────
choco install -y --no-progress temurin17
choco install -y --no-progress git
choco install -y --no-progress nssm

# Refresh PATH after installs
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + `
            [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "--- Packages installed ---"

# ── 3. Jenkins agent workspace directory ─────────────────────────────────────
New-Item -Path "C:\jenkins-agent" -ItemType Directory -Force | Out-Null
Write-Host "--- Created C:\jenkins-agent ---"

# ── 4. Print connection instructions ─────────────────────────────────────────
Write-Host "==================================================================="
Write-Host " Jenkins Agent Windows — Prerequisites Ready"
Write-Host ""
Write-Host " Connect this node in Jenkins UI:"
Write-Host "   Label  : windows-agent"
Write-Host "   Root   : C:\jenkins-agent"
Write-Host "   Launch : Launch agent by connecting it to the controller (JNLP)"
Write-Host ""
Write-Host " After adding in Jenkins UI, copy the agent.jar and secret, then run:"
Write-Host "   nssm install JenkinsAgent java"
Write-Host "   nssm set JenkinsAgent AppParameters -jar C:\jenkins-agent\agent.jar ``"
Write-Host "     -url http://<MASTER_IP>:8080 -secret <SECRET> -name windows-agent"
Write-Host "   nssm set JenkinsAgent AppDirectory C:\jenkins-agent"
Write-Host "   nssm start JenkinsAgent"
Write-Host ""
Write-Host " SSM access: aws ssm start-session --target <instance-id>"
Write-Host "==================================================================="
Write-Host "Bootstrap complete: $(Get-Date)"

Stop-Transcript
</powershell>
<persist>true</persist>
