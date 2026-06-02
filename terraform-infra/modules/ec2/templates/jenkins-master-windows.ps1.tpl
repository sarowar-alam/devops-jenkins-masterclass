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

# ── 2. Install Java 21 FIRST, set JAVA_HOME, then install Jenkins ─────────────
# CRITICAL ORDER: JAVA_HOME must be set before Jenkins MSI runs,
# otherwise the Jenkins service registration fails (error 1060).
choco install -y --no-progress temurin21

# Set JAVA_HOME immediately after Java install, before Jenkins MSI runs
$jdkDir = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory `
  -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*21*' } `
  | Sort-Object Name -Descending | Select-Object -First 1
if ($jdkDir) {
  $javaHome = $jdkDir.FullName
  [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "Machine")
  $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
  if ($machinePath -notlike "*$javaHome\bin*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$javaHome\bin;$machinePath", "Machine")
  }
  $env:JAVA_HOME = $javaHome
  $env:Path = "$javaHome\bin;$env:Path"
  Write-Host "--- JAVA_HOME set to: $javaHome ---"
} else {
  Write-Host "ERROR: Could not locate temurin21 JDK — aborting"
  Get-ChildItem "C:\Program Files\Eclipse Adoptium" -ErrorAction SilentlyContinue | Select-Object Name
  Stop-Transcript; exit 1
}

# Now install Jenkins (MSI will find Java via JAVA_HOME + PATH)
choco install -y --no-progress jenkins
choco install -y --no-progress git
choco install -y --no-progress awscli

# Refresh PATH in current session after all installs
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + `
            [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "--- Packages installed ---"

# ── 2b. Patch jenkins.xml to use explicit Java path (belt + suspenders) ───────
# Even if JAVA_HOME env var is not inherited by the service, the explicit path works.
$jenkinsXml = "C:\Program Files\Jenkins\jenkins.xml"
if (Test-Path $jenkinsXml) {
  $xmlContent = Get-Content $jenkinsXml -Raw
  $javaExe = "$javaHome\bin\java.exe" -replace '\\', '\\'
  # Replace any existing <executable> line with our explicit java path
  $xmlContent = $xmlContent -replace '<executable>[^<]*</executable>', "<executable>$javaHome\bin\java.exe</executable>"
  Set-Content $jenkinsXml $xmlContent -Encoding UTF8
  Write-Host "--- jenkins.xml patched with explicit java path ---"
} else {
  Write-Host "WARNING: jenkins.xml not found at expected path"
}

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
# Stop first in case choco auto-started it before JAVA_HOME was set
Stop-Service -Name Jenkins -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Set-Service -Name Jenkins -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name Jenkins -ErrorAction SilentlyContinue
Write-Host "--- Jenkins service started ---"

# ── 5. Wait for initialAdminPassword ─────────────────────────────────────────
# Jenkins home path varies by install method — check all known locations.
Write-Host "--- Waiting for Jenkins initialAdminPassword ---"
$maxWait = 600
$elapsed = 0
$passFile = $null
$candidatePaths = @(
  "C:\ProgramData\Jenkins\.jenkins\secrets\initialAdminPassword",
  "C:\Windows\System32\config\systemprofile\AppData\Local\Jenkins\.jenkins\secrets\initialAdminPassword",
  "C:\Windows\ServiceProfiles\LocalSystem\AppData\Local\Jenkins\.jenkins\secrets\initialAdminPassword"
)

while ($true) {
  foreach ($p in $candidatePaths) {
    if (Test-Path $p) { $passFile = $p; break }
  }
  if ($passFile) { break }
  if ($elapsed -ge $maxWait) {
    Write-Host "ERROR: Jenkins did not write initialAdminPassword within $maxWait seconds"
    Write-Host "Service status:"
    Get-Service Jenkins | Select-Object Name, Status, StartType | Format-List
    Write-Host "Checked paths:"
    $candidatePaths | ForEach-Object { Write-Host "  $_" }
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
