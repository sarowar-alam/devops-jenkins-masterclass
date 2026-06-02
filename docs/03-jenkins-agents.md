# SL#3 — Jenkins Agent Nodes Setup Guide

> **Starting point:** You have the **Windows Server 2019 Jenkins Master** running from SL#2.  
> You will connect two agent nodes to it:  
> - **Agent 1:** Ubuntu 24.04 Linux (connected via SSH)  
> - **Agent 2:** Windows Server (connected via JNLP, running as a Windows Service using NSSM)

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│         WINDOWS JENKINS MASTER              │
│         http://<MASTER_IP>:8080             │
│                                             │
│  Nodes registered:                          │
│  ● Built-in Node   (controller itself)      │
│  ● linux-agent     (Ubuntu 24.04 via SSH)   │
│  ● windows-agent   (Windows via JNLP/NSSM) │
└─────────────────┬──────────────────┬────────┘
                  │ SSH              │ JNLP (WebSocket)
                  ▼                  ▼
    ┌─────────────────────┐  ┌─────────────────────┐
    │  LINUX AGENT        │  │  WINDOWS AGENT      │
    │  Ubuntu 24.04 LTS   │  │  Windows Server     │
    │  Label: linux-agent │  │  Label:windows-agent│
    └─────────────────────┘  └─────────────────────┘
```

---

## Agent 1 — Ubuntu 24.04 Linux Agent (SSH Launch)

### How SSH Launch Works

The Jenkins master SSHes into the agent machine, copies the `agent.jar` file, and starts the agent process. You do not need to do anything on the agent after setup — the master manages the connection.

---

### Part A — Prepare the Linux Agent Machine

Run all commands on the **Ubuntu 24.04 agent machine** (not the master).

#### Step A1 — Install Java 21

The agent requires the same Java version as the master:

```bash
sudo apt update
sudo apt install -y fontconfig openjdk-21-jre

# Verify
java -version
# Expected: openjdk version "21.0.x"
```

#### Step A2 — Create the `jenkins` OS User

Create a dedicated user for Jenkins agent processes. This user should not have sudo access.

```bash
# Create jenkins user with home directory, no login shell
sudo useradd -m -s /bin/bash jenkins

# Create the workspace directory
sudo mkdir -p /home/jenkins/workspace

# Set correct ownership
sudo chown -R jenkins:jenkins /home/jenkins/
```

#### Step A3 — Set Up SSH Key Authentication

The master will authenticate to the agent using an SSH key pair.  
You will generate the key pair **on the master**, then place the public key on the agent.

**On the Windows Master — open PowerShell:**

```powershell
# Generate an SSH key pair for Jenkins agent connections
# This creates two files: jenkins_agent_key (private) and jenkins_agent_key.pub (public)
ssh-keygen -t ed25519 -C "jenkins-agent-key" -f C:\jenkins-agent-keys\jenkins_agent_key -N '""'

# Display the public key — copy this value
Get-Content "C:\jenkins-agent-keys\jenkins_agent_key.pub"
```

> If `ssh-keygen` is not available, install **OpenSSH Client** via:  
> Settings → Optional Features → Add a feature → OpenSSH Client

**Back on the Linux Agent machine:**

```bash
# Switch to jenkins user
sudo su - jenkins

# Create .ssh directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Paste the public key from the master into authorized_keys
# Replace the value below with your actual public key
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... jenkins-agent-key" >> ~/.ssh/authorized_keys

chmod 600 ~/.ssh/authorized_keys

# Return to ubuntu user
exit
```

#### Step A4 — Test SSH Connection from Master to Agent

**On the Windows Master:**

```powershell
# Test that master can SSH into the agent as the jenkins user
ssh -i C:\jenkins-agent-keys\jenkins_agent_key jenkins@<AGENT_LINUX_IP>

# You should get a shell prompt on the agent
# Type: exit  to return
```

If this works, proceed. If not, check:
- Linux agent firewall: `sudo ufw allow 22`
- AWS Security Group: port 22 inbound
- `authorized_keys` file permissions (must be 600)

---

### Part B — Register the Linux Agent in Jenkins Master UI

Run the steps below in the **Windows Master's** Jenkins web UI.

#### Step B1 — Add SSH Private Key to Jenkins Credentials

1. `Manage Jenkins` → `Credentials` → `System` → `Global credentials` → `Add Credentials`
2. Fill in:
   - **Kind:** `SSH Username with private key`
   - **ID:** `linux-agent-ssh-key` *(remember this ID)*
   - **Description:** `Linux Agent SSH Private Key`
   - **Username:** `jenkins`
   - **Private Key:** Select `Enter directly` → paste the contents of `C:\jenkins-agent-keys\jenkins_agent_key`
3. Click **Create**

#### Step B2 — Create the Linux Agent Node

1. `Manage Jenkins` → `Nodes` → `New Node`
2. **Node name:** `linux-agent`
3. Select **Permanent Agent** → click **Create**
4. Fill in the configuration:

| Field | Value |
|---|---|
| **Description** | Ubuntu 24.04 LTS Linux Build Agent |
| **Number of executors** | `2` |
| **Remote root directory** | `/home/jenkins/workspace` |
| **Labels** | `linux-agent` |
| **Usage** | `Only build jobs with label expressions matching this node` |
| **Launch method** | `Launch agents via SSH` |
| **Host** | `<AGENT_LINUX_IP>` |
| **Credentials** | `linux-agent-ssh-key` (created in Step B1) |
| **Host Key Verification Strategy** | `Non verifying Verification Strategy` (classroom) or `Known hosts file` (production) |

5. Click **Save**

#### Step B3 — Verify the Linux Agent Connection

1. `Manage Jenkins` → `Nodes` → click on `linux-agent`
2. Click **"Launch agent"** if it didn't connect automatically
3. Click **"Log"** — you should see:

```
[06/02/26 10:00:00] [SSH] Opening SSH connection to 10.0.0.50:22
[06/02/26 10:00:01] [SSH] Authentication successful
Agent successfully connected and online
```

4. On the **Nodes** overview page, `linux-agent` should show a **green circle** ✅

---

## Agent 2 — Windows Agent (JNLP via WebSocket — Windows Service)

### How JNLP Launch Works

Unlike SSH launch, the agent machine **initiates the connection to the master** by running `agent.jar`. This is the standard approach for Windows agents where the master cannot SSH in. We install it as a **Windows Service using NSSM** so it starts automatically on boot and restarts on crashes.

---

### Part A — Prepare the Windows Agent Machine

Run all steps on the **Windows agent machine** (not the master).

#### Step A1 — Install Java 21 JDK

1. Download JDK 21 from: [https://adoptium.net/temurin/releases/](https://adoptium.net/temurin/releases/)
2. Select: Version 21, Windows, x64, JDK, `.msi`
3. Run the installer — ensure `JAVA_HOME` and `PATH` options are checked
4. Verify:

```powershell
java -version
# Expected: openjdk version "21.0.x"
$env:JAVA_HOME
# Expected: C:\Program Files\Eclipse Adoptium\jdk-21.x.x.x-hotspot
```

#### Step A2 — Create Agent Working Directories

```powershell
# Run as Administrator
New-Item -ItemType Directory -Path "C:\jenkins-agent\workspace" -Force
New-Item -ItemType Directory -Path "C:\jenkins-agent\logs" -Force
New-Item -ItemType Directory -Path "C:\jenkins-agent" -Force
```

---

### Part B — Register the Windows Agent in Jenkins Master UI

#### Step B1 — Configure the Agent Node

1. In the Windows Master UI: `Manage Jenkins` → `Nodes` → `New Node`
2. **Node name:** `windows-agent`
3. Select **Permanent Agent** → click **Create**
4. Fill in:

| Field | Value |
|---|---|
| **Description** | Windows Server Build Agent |
| **Number of executors** | `2` |
| **Remote root directory** | `C:\jenkins-agent\workspace` |
| **Labels** | `windows-agent` |
| **Usage** | `Only build jobs with label expressions matching this node` |
| **Launch method** | `Launch agent by connecting it to the controller` |

5. Click **Save**

#### Step B2 — Get the Agent Secret Token

1. `Manage Jenkins` → `Nodes` → click on `windows-agent`
2. You will see a command like:

```
java -jar agent.jar -url http://<MASTER_IP>:8080/ -secret abc123def456... -name windows-agent -workDir "C:\jenkins-agent\workspace"
```

3. **Copy the `-secret` value** — this is the agent's authentication token.

---

### Part C — Download `agent.jar` on the Windows Agent Machine

**On the Windows agent machine:**

```powershell
# Download agent.jar from the Jenkins master
# Replace <MASTER_IP> with your Windows master's IP
Invoke-WebRequest `
  -Uri "http://<MASTER_IP>:8080/jnlpJars/agent.jar" `
  -OutFile "C:\jenkins-agent\agent.jar"

# Verify the file was downloaded
Get-Item "C:\jenkins-agent\agent.jar"
```

---

### Part D — Test the Agent Connection Manually

Before installing as a service, verify the connection works manually:

```powershell
# Run this in PowerShell on the Windows agent machine
# Replace <MASTER_IP> and <SECRET_TOKEN> with your actual values
java -jar C:\jenkins-agent\agent.jar `
  -url "http://<MASTER_IP>:8080/" `
  -secret "<SECRET_TOKEN>" `
  -name "windows-agent" `
  -workDir "C:\jenkins-agent\workspace"
```

In the Jenkins Master UI → Nodes → `windows-agent`, it should show **Connected**.  
Press `Ctrl+C` to stop the manual run — proceed to install as a Windows Service.

---

### Part E — Install NSSM (Non-Sucking Service Manager)

NSSM wraps any executable as a Windows Service with proper start/stop/restart behavior and log management.

#### Step E1 — Download NSSM

```powershell
# Download NSSM
Invoke-WebRequest `
  -Uri "https://nssm.cc/release/nssm-2.24.zip" `
  -OutFile "C:\Temp\nssm.zip"

# Extract
Expand-Archive -Path "C:\Temp\nssm.zip" -DestinationPath "C:\Temp\nssm"

# Copy the 64-bit executable to a permanent location
Copy-Item "C:\Temp\nssm\nssm-2.24\win64\nssm.exe" -Destination "C:\Windows\System32\nssm.exe"

# Verify
nssm version
```

---

### Part F — Install Jenkins Agent as a Windows Service

Run all commands as **Administrator** in PowerShell:

#### Step F1 — Install the Service

```powershell
# Install service named "JenkinsAgent"
nssm install JenkinsAgent "C:\Program Files\Eclipse Adoptium\jdk-21.x.x.x-hotspot\bin\java.exe"
```

> Replace the Java path with your actual `$env:JAVA_HOME\bin\java.exe`

```powershell
# You can find the exact path with:
$env:JAVA_HOME + "\bin\java.exe"
```

#### Step F2 — Configure Service Arguments

```powershell
# Set the arguments for the java process
# Replace <MASTER_IP> and <SECRET_TOKEN> with your actual values
nssm set JenkinsAgent AppParameters `
  "-jar C:\jenkins-agent\agent.jar -url http://<MASTER_IP>:8080/ -secret <SECRET_TOKEN> -name windows-agent -workDir C:\jenkins-agent\workspace"
```

#### Step F3 — Configure Working Directory

```powershell
nssm set JenkinsAgent AppDirectory "C:\jenkins-agent"
```

#### Step F4 — Configure Log Files

```powershell
# Stdout log
nssm set JenkinsAgent AppStdout "C:\jenkins-agent\logs\agent.log"

# Stderr log
nssm set JenkinsAgent AppStderr "C:\jenkins-agent\logs\agent-error.log"

# Rotate logs so they don't grow forever
nssm set JenkinsAgent AppStdoutCreationDisposition 4
nssm set JenkinsAgent AppStderrCreationDisposition 4
```

#### Step F5 — Configure Auto-Restart on Failure

```powershell
# Restart the service if it crashes, after 10 seconds
nssm set JenkinsAgent AppRestartDelay 10000
nssm set JenkinsAgent AppThrottle 1500
```

#### Step F6 — Set Startup Type to Automatic

```powershell
nssm set JenkinsAgent Start SERVICE_AUTO_START
```

#### Step F7 — Start the Service

```powershell
nssm start JenkinsAgent

# Verify it is running
Get-Service -Name JenkinsAgent

# Expected:
# Status   Name            DisplayName
# ------   ----            -----------
# Running  JenkinsAgent    JenkinsAgent
```

---

### Part G — Verify the Windows Agent in Jenkins UI

1. `Manage Jenkins` → `Nodes` → click `windows-agent`
2. Click **"Log"** — you should see:

```
INFO: Remoting version: ...
INFO: This is a Windows agent
Agent successfully connected and online
```

3. On the Nodes overview page, `windows-agent` should show a **green circle** ✅

---

### Part H — Verify Both Agents Are Connected

In the Jenkins Master UI, go to: `Manage Jenkins` → `Nodes`

You should see:

| Name | Architecture | Status | Labels |
|---|---|---|---|
| Built-In Node | Controller | ✅ Online | `built-in` |
| linux-agent | Linux (Ubuntu 24.04) | ✅ Online | `linux-agent` |
| windows-agent | Windows | ✅ Online | `windows-agent` |

---

## Windows Agent Service Management

Use these commands to manage the JenkinsAgent service going forward:

```powershell
# Check status
Get-Service -Name JenkinsAgent

# Stop the agent
Stop-Service -Name JenkinsAgent

# Start the agent
Start-Service -Name JenkinsAgent

# Restart the agent (after Jenkins master restarts)
Restart-Service -Name JenkinsAgent

# View recent logs
Get-Content "C:\jenkins-agent\logs\agent.log" -Tail 50

# View errors
Get-Content "C:\jenkins-agent\logs\agent-error.log" -Tail 20

# Remove the service entirely (if you need to reconfigure)
nssm remove JenkinsAgent confirm
```

---

## Updating the Secret Token

If the agent secret changes (e.g. after Jenkins reinstall):

```powershell
# Stop the service
Stop-Service -Name JenkinsAgent

# Update the secret in NSSM
nssm set JenkinsAgent AppParameters `
  "-jar C:\jenkins-agent\agent.jar -url http://<MASTER_IP>:8080/ -secret <NEW_SECRET_TOKEN> -name windows-agent -workDir C:\jenkins-agent\workspace"

# Start the service again
Start-Service -Name JenkinsAgent
```

---

## Troubleshooting

### Linux Agent — "SSH connection refused"

```bash
# On the agent: verify SSH service is running
sudo systemctl status sshd

# Start if not running
sudo systemctl start sshd
sudo systemctl enable sshd

# Verify jenkins user exists
id jenkins

# Verify authorized_keys
sudo cat /home/jenkins/.ssh/authorized_keys
```

### Linux Agent — "Host key verification failed"

In the Jenkins node configuration, change **Host Key Verification Strategy** to:  
`Non verifying Verification Strategy` for classroom/testing, or  
`Manually provided key` for production (paste the agent's SSH host key).

### Windows Agent — Service starts but agent shows offline

```powershell
# Check the error log
Get-Content "C:\jenkins-agent\logs\agent-error.log" -Tail 30

# Common causes:
# 1. Wrong secret token — regenerate from Jenkins UI and update NSSM config
# 2. Master URL wrong — verify http://<MASTER_IP>:8080/ is reachable from agent
# 3. Port 50000 blocked — verify firewall allows agent → master on port 50000
# 4. Java path wrong — verify java.exe path in NSSM config
```

### Windows Agent — Port 50000 connection issues

Ensure port 50000 is open on the **master** (inbound) and on the **agent** (outbound):

```powershell
# On master: verify port 50000 is open
Get-NetFirewallRule -DisplayName "Jenkins JNLP*"

# Test connectivity from agent to master
Test-NetConnection -ComputerName <MASTER_IP> -Port 50000
# Expected: TcpTestSucceeded: True
```

Also verify in Jenkins: `Manage Jenkins` → `Security` → ensure **"TCP port for inbound agents"** is set to **Fixed: 50000** (not Disabled).

---

## Labels Reference

Labels route specific pipeline jobs to specific agents:

```groovy
// Run on the controller itself
agent { label 'built-in' }

// Run on the Linux agent
agent { label 'linux-agent' }

// Run on the Windows agent
agent { label 'windows-agent' }

// Run on any available agent (not recommended for this course)
agent any

// Run on either linux-agent OR windows-agent
agent { label 'linux-agent || windows-agent' }
```

---

## Project Lead

**MD Sarowar Alam**
Lead DevOps Engineer, WPP Production
📧 Email: [sarowar@hotmail.com](mailto:sarowar@hotmail.com)
🔗 LinkedIn: https://www.linkedin.com/in/sarowar/

---
