<powershell>
# jenkins-master-windows.ps1.tpl
# Terraform vars: ${project_name}, ${environment}
# All PowerShell vars use $var syntax (no braces) to avoid Terraform interpolation.

Start-Transcript -Path "C:\jenkins-bootstrap.log" -Force

Write-Host "==================================================================="
Write-Host " Jenkins Master Windows Bootstrap"
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

# ── 2. Install Java 17, Jenkins, Git, AWS CLI ────────────────────────────────
choco install -y --no-progress temurin17
choco install -y --no-progress jenkins
choco install -y --no-progress git
choco install -y --no-progress awscli

# Refresh PATH after package installs
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + `
            [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "--- Packages installed ---"

# ── 3. Firewall rules ────────────────────────────────────────────────────────
New-NetFirewallRule `
  -DisplayName "Jenkins HTTP 8080" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8080 `
  -Action Allow `
  -ErrorAction SilentlyContinue

New-NetFirewallRule `
  -DisplayName "Jenkins JNLP 50000" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 50000 `
  -Action Allow `
  -ErrorAction SilentlyContinue

Write-Host "--- Firewall rules created ---"

# ── 4. Ensure Jenkins service is running ─────────────────────────────────────
Set-Service -Name Jenkins -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name Jenkins -ErrorAction SilentlyContinue
Write-Host "--- Jenkins service started ---"

# ── 5. Wait for initialAdminPassword ─────────────────────────────────────────
Write-Host "--- Waiting for Jenkins initialAdminPassword ---"
$maxWait  = 300
$elapsed  = 0
$passFile = "C:\ProgramData\Jenkins\.jenkins\secrets\initialAdminPassword"

while (-not (Test-Path $passFile)) {
  if ($elapsed -ge $maxWait) {
    Write-Host "ERROR: Jenkins did not write initialAdminPassword within $maxWait seconds"
    Write-Host "Check: Get-Service Jenkins | Select-Object Status"
    break
  }
  Start-Sleep -Seconds 10
  $elapsed += 10
  Write-Host "Waiting... ($elapsed/$maxWait seconds)"
}

if (Test-Path $passFile) {
  Write-Host "==================================================================="
  Write-Host " Jenkins Initial Admin Password:"
  Get-Content $passFile
  Write-Host "==================================================================="
}

Write-Host "Bootstrap complete: $(Get-Date)"

Stop-Transcript
</powershell>
<persist>true</persist>
