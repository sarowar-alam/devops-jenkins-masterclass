# SL#2 — Jenkins Installation Guide

> Two completely independent Jenkins Masters:  
> **Section A** — Ubuntu 24.04 LTS (Linux)  
> **Section B** — Windows Server 2019  
> Both result in a fully operational Jenkins Master at `http://<IP>:8080`

---

## Section A — Install Jenkins Master on Ubuntu 24.04 LTS

### Prerequisites

| Requirement | Minimum | Recommended |
|---|---|---|
| CPU | 1 core | 2 cores |
| RAM | 2 GB | 4 GB |
| Disk | 20 GB | 50 GB |
| OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| Java | Java 21 (JRE) | Java 21 (JDK) |
| Port | 8080 open inbound | 8080 + 50000 (agent JNLP) |

> **Note:** Jenkins requires Java. It does **not** bundle Java. You must install it first.

---

### Step 1 — Update the System

```bash
sudo apt update && sudo apt upgrade -y
```

---

### Step 2 — Install Java 21

Jenkins LTS 2.492+ requires Java 21. We use Java 21:

```bash
sudo apt install -y fontconfig openjdk-21-jre

# Verify installation
java -version
# Expected output:
# openjdk version "21.0.x" ...
```

---

### Step 3 — Add the Jenkins Repository

Jenkins provides an official apt repository. Add the GPG key and source list:

```bash
# Download and add the Jenkins GPG key (rotated Dec 2025 — use 2026 key)
sudo install -m 0755 -d /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

# Add the Jenkins apt repository
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Update package index to include the new repo
sudo apt update
```

---

### Step 4 — Install Jenkins

```bash
sudo apt install -y jenkins

# Verify Jenkins service was created
sudo systemctl status jenkins
```

---

### Step 5 — Enable and Start Jenkins

```bash
# Enable Jenkins to start automatically on boot
sudo systemctl enable jenkins

# Start the Jenkins service now
sudo systemctl start jenkins

# Confirm it is running
sudo systemctl status jenkins
# Look for: Active: active (running)
```

---

### Step 6 — Configure the Firewall

If UFW is active, open port 8080:

```bash
sudo ufw allow 8080/tcp
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status
```

If you are on AWS EC2: open port 8080 in the **Security Group** inbound rules instead.

> **AWS EC2 Security Group rule:**  
> Type: Custom TCP | Port: 8080 | Source: My IP (or 0.0.0.0/0 for classroom use)  
> Type: Custom TCP | Port: 50000 | Source: 0.0.0.0/0 (for JNLP agents)

---

### Step 7 — Get the Initial Admin Password

On first start, Jenkins creates a one-time setup password:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
# Example output: a8f3c2d1e5b4a9f7c3e2d1b5a8f3c2d1
```

Copy this password — you will need it in Step 8.

---

### Step 8 — Complete the Web UI Setup

1. Open a browser and navigate to: `http://<YOUR_SERVER_IP>:8080`

2. **Unlock Jenkins:**  
   Paste the password from Step 7 into the "Administrator password" field → click **Continue**

3. **Install Suggested Plugins:**  
   Click **"Install suggested plugins"** and wait for all plugins to install (2–5 minutes)

4. **Create the First Admin User:**
   - Username: `admin` (or your choice)
   - Password: choose a strong password
   - Full name and email
   - Click **Save and Continue**

5. **Jenkins URL:**  
   Set to `http://<YOUR_SERVER_IP>:8080/` → click **Save and Finish**

6. Click **"Start using Jenkins"** — you are now on the Jenkins dashboard.

---

### Step 9 — Verify the Installation

```bash
# Check Jenkins version
jenkins --version

# Check the Jenkins process
ps aux | grep jenkins

# Check port 8080 is listening
sudo ss -tlnp | grep 8080

# View Jenkins logs (useful for troubleshooting)
sudo journalctl -u jenkins -f
```

---

### Step 10 — Install Required Plugins

Navigate to: `Manage Jenkins → Plugins → Available plugins`

Search for and install each plugin below:

| Plugin | Why You Need It |
|---|---|
| **SSH Agent** | Inject SSH keys into pipeline steps (EC2 access) |
| **Email Extension** | Send rich HTML emails via AWS SES SMTP |
| **Copy Artifact** | Share `build-manifest.json` between RC and Deploy pipelines |
| **AWS Credentials** | Native AWS credential type for ECR/STS |
| **Docker Pipeline** | Use `docker build`, `docker push` natively in pipelines |
| **Credentials Binding** | `withCredentials { }` block in pipelines |
| **Timestamper** | Adds timestamps to all console output |
| **Git Parameter** | Let users pick a branch/tag as a build parameter |

After selecting all plugins, click **Install** and wait for completion.  
Tick **"Restart Jenkins when installation is complete"** if prompted.

---

### Step 11 — Configure Jenkins System Settings

Navigate to: `Manage Jenkins → System`

| Setting | Value |
|---|---|
| **Jenkins URL** | `http://<YOUR_IP>:8080/` |
| **System Admin e-mail address** | `jenkins@yourdomain.com` |
| **# of executors** | `2` (on the controller — keep low, builds should run on agents) |

Click **Save**.

---

### Ubuntu Jenkins — File Locations Reference

| Path | Purpose |
|---|---|
| `/var/lib/jenkins/` | Jenkins home directory (jobs, configs, credentials) |
| `/var/lib/jenkins/secrets/initialAdminPassword` | First-run unlock password |
| `/var/lib/jenkins/jobs/` | All job configurations |
| `/var/lib/jenkins/plugins/` | Installed plugins |
| `/var/log/jenkins/jenkins.log` | Application log |
| `/etc/default/jenkins` | Service configuration (port, Java args) |

### Changing the Port (Optional)

If you want Jenkins on a port other than 8080:

```bash
sudo nano /etc/default/jenkins
# Change: JENKINS_PORT=8080  →  JENKINS_PORT=9090

sudo systemctl restart jenkins
```

---

---

## Section B — Install Jenkins Master on Windows Server 2019

### Prerequisites

| Requirement | Minimum | Recommended |
|---|---|---|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Disk | 40 GB | 80 GB |
| OS | Windows Server 2019 | Windows Server 2019 (or 2022) |
| Java | JDK 21 | JDK 21 |
| Port | 8080 open inbound | 8080 + 50000 |
| Account | Local Administrator | Domain or local Admin |

---

### Step 1 — Install Java 21 (JDK)

Jenkins LTS 2.492+ requires Java 21. A full JDK is recommended on Windows.

1. Go to: [https://adoptium.net/temurin/releases/](https://adoptium.net/temurin/releases/)
2. Select: **Version 21**, **Windows**, **x64**, **JDK**, `.msi` package
3. Download and run the `.msi` installer
4. During installation, ensure these options are checked:
   - ✅ **Add to PATH**
   - ✅ **Set JAVA_HOME variable**
5. Complete the installation

> **Or via Chocolatey (recommended for automation):**
> ```powershell
> choco install -y temurin21
> ```

**Verify in PowerShell (run as Administrator):**

```powershell
java -version
# Expected: openjdk version "21.0.x" ...

$env:JAVA_HOME
# Expected: C:\Program Files\Eclipse Adoptium\jdk-21.x.x.x-hotspot
```

---

### Step 2 — Download the Jenkins Windows Installer

1. Go to: [https://www.jenkins.io/download/](https://www.jenkins.io/download/)
2. Under **"Long-Term Support (LTS)"**, click **Windows** to download `jenkins.msi`

> **Important:** Always download the **LTS** version for production use, not the Weekly release.

---

### Step 3 — Run the Jenkins MSI Installer

1. **Right-click** `jenkins.msi` → **Run as administrator**

2. Click **Next** on the Welcome screen

3. **Destination Folder:** Accept the default `C:\Program Files\Jenkins\` or choose your path

4. **Service Logon Credentials:**
   - Select **"Run service as LocalSystem"** (simplest for getting started)
   - For production: create a dedicated `jenkins` Windows user account with minimal permissions
   - Click **Test Credentials** to verify, then **Next**

5. **Port Configuration:**
   - Default port: `8080`
   - Click **Test Port** to confirm it is available
   - If port 8080 is in use, change it here (e.g. `8090`)
   - Click **Next**

6. **Select Java Home:**
   - The installer should auto-detect `JAVA_HOME`
   - If not, browse to your JDK installation folder (e.g. `C:\Program Files\Eclipse Adoptium\jdk-21.x.x.x-hotspot`)
   - Click **Next**

7. **Custom Setup:** Leave defaults → **Next**

8. Click **Install** and wait (2–3 minutes)

9. Click **Finish**

---

### Step 4 — Jenkins Windows Service (Auto-Configured)

The MSI installer automatically:
- Creates a Windows Service named **"Jenkins"**
- Sets it to start **Automatically** on boot
- Starts the service immediately

**Verify in PowerShell:**

```powershell
# Check Jenkins service status
Get-Service -Name Jenkins

# Expected output:
# Status   Name    DisplayName
# ------   ----    -----------
# Running  Jenkins Jenkins

# View service details
Get-Service -Name Jenkins | Format-List *
```

**View from Windows UI:**
- Press `Win + R` → type `services.msc` → Enter
- Find **Jenkins** in the list
- Status: **Running**, Startup type: **Automatic**

---

### Step 5 — Configure Windows Firewall

Open port 8080 for Jenkins UI access:

```powershell
# Run as Administrator
New-NetFirewallRule `
  -DisplayName "Jenkins Web UI" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8080 `
  -Action Allow

# Open port 50000 for JNLP agent connections
New-NetFirewallRule `
  -DisplayName "Jenkins JNLP Agents" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 50000 `
  -Action Allow

# Verify rules were created
Get-NetFirewallRule -DisplayName "Jenkins*" | Select-Object DisplayName, Enabled, Direction
```

If you are on **AWS EC2 Windows**, also add inbound rules to the Security Group:
- Port 8080 — Jenkins Web UI
- Port 50000 — Jenkins JNLP agent connections

---

### Step 6 — Get the Initial Admin Password

```powershell
# Read the initial unlock password
Get-Content "C:\Program Files\Jenkins\secrets\initialAdminPassword"
# Example: a8f3c2d1e5b4a9f7c3e2d1b5a8f3c2d1
```

Copy this value — you need it for the web UI setup.

---

### Step 7 — Complete the Web UI Setup

1. Open a browser and navigate to: `http://localhost:8080` (or `http://<SERVER_IP>:8080` from a remote machine)

2. **Unlock Jenkins:** Paste the password from Step 6 → **Continue**

3. **Install Suggested Plugins:** Click **"Install suggested plugins"** → wait 3–5 minutes

4. **Create Admin User:** Fill in username, password, full name, email → **Save and Continue**

5. **Jenkins URL:** Set to `http://<SERVER_IP>:8080/` → **Save and Finish**

6. Click **"Start using Jenkins"**

---

### Step 8 — Install Required Plugins (Windows Master)

Same plugins as the Linux master. Navigate to:  
`Manage Jenkins → Plugins → Available plugins`

Install: SSH Agent, Email Extension, Copy Artifact, AWS Credentials, Docker Pipeline, Credentials Binding, Timestamper, Git Parameter

---

### Step 9 — Jenkins Service Management (Windows)

Use PowerShell to manage the Jenkins service:

```powershell
# Start Jenkins
Start-Service -Name Jenkins

# Stop Jenkins
Stop-Service -Name Jenkins

# Restart Jenkins (after plugin installs)
Restart-Service -Name Jenkins

# Check status
Get-Service -Name Jenkins

# View Jenkins logs in real-time (Event Viewer alternative)
Get-Content "C:\Program Files\Jenkins\jenkins.out.log" -Wait -Tail 50

# Or check Windows Event Log
Get-WinEvent -LogName Application | Where-Object { $_.ProviderName -eq 'Jenkins' } | Select-Object -First 20
```

---

### Windows Jenkins — File Locations Reference

| Path | Purpose |
|---|---|
| `C:\Program Files\Jenkins\` | Jenkins installation directory |
| `C:\Program Files\Jenkins\secrets\initialAdminPassword` | First-run unlock password |
| `C:\Program Files\Jenkins\jobs\` | All job configurations |
| `C:\Program Files\Jenkins\plugins\` | Installed plugins |
| `C:\Program Files\Jenkins\jenkins.out.log` | stdout log |
| `C:\Program Files\Jenkins\jenkins.err.log` | stderr log |
| `C:\Program Files\Jenkins\jenkins.xml` | Windows service configuration |

### Changing the Port on Windows

Edit the service configuration file:

```powershell
# Open the service config
notepad "C:\Program Files\Jenkins\jenkins.xml"
```

Find this line and change the port number:

```xml
<arguments>-Xrs -Xmx256m -Dhudson.lifecycle=hudson.lifecycle.WindowsServiceLifecycle
  -jar "C:\Program Files\Jenkins\jenkins.war" --httpPort=8080 --webroot=...</arguments>
```

Change `--httpPort=8080` to your desired port, save, then restart the service.

---

## Comparing Both Masters

| | Ubuntu 24.04 Master | Windows Server 2019 Master |
|---|---|---|
| **Access URL** | `http://<LINUX_IP>:8080` | `http://<WINDOWS_IP>:8080` |
| **Initial password location** | `/var/lib/jenkins/secrets/initialAdminPassword` | `C:\Program Files\Jenkins\secrets\initialAdminPassword` |
| **Service management** | `systemctl start/stop/restart jenkins` | `Start-Service/Stop-Service Jenkins` |
| **Logs** | `journalctl -u jenkins -f` | `C:\Program Files\Jenkins\jenkins.out.log` |
| **Jenkins home** | `/var/lib/jenkins/` | `C:\Program Files\Jenkins\` |
| **Config file** | `/etc/default/jenkins` | `C:\Program Files\Jenkins\jenkins.xml` |
| **Auto-start on boot** | `systemctl enable jenkins` (set during install) | Automatic (set by MSI installer) |

---

## Troubleshooting

### Ubuntu — Jenkins won't start

```bash
# Check for Java issues
java -version

# Check Jenkins log
sudo journalctl -u jenkins -n 50 --no-pager

# Check if port 8080 is already in use
sudo ss -tlnp | grep 8080

# If port is in use, find the process
sudo lsof -i :8080
```

### Windows — Jenkins won't start

```powershell
# Check the error log
Get-Content "C:\Program Files\Jenkins\jenkins.err.log" -Tail 30

# Check if Java is correctly configured
$env:JAVA_HOME
java -version

# Check if port 8080 is in use
netstat -ano | findstr :8080

# If port in use, find the process ID and kill it
taskkill /F /PID <PID>

# Restart Jenkins service
Restart-Service -Name Jenkins
```

### Both — Can't access UI from remote machine

1. Confirm the server IP address is correct
2. Verify Jenkins is listening: `netstat -tlnp | grep 8080` (Linux) or `netstat -ano | findstr :8080` (Windows)
3. Verify firewall allows port 8080
4. On AWS: verify Security Group inbound rule for port 8080
5. Try accessing from the server itself first: `curl http://localhost:8080`
