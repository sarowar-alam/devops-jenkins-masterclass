# SL#0 — Master Implementation Guide

> **Purpose of this document:** the single starting point for standing up this repo's entire Jenkins
> CI/CD environment and running every pipeline in the correct order — end to end, from an empty AWS
> account to a deployed BMI Health Tracker application.
>
> This guide **links to** the detailed session docs (`docs/01` → `docs/07`) instead of repeating their
> full content, but includes condensed, copy-pasteable steps for everything — including the two ways
> to stand up Jenkins (Terraform-automated vs fully manual) for **both Linux and Windows**, which are
> not fully consolidated anywhere else in the repo.

---

## Table of Contents

1. [Two Ways to Get Jenkins Running](#1-two-ways-to-get-jenkins-running)
2. [Path A — Automated via `terraform-infra/`](#2-path-a--automated-via-terraform-infra)
3. [Path B — Fully Manual Installation](#3-path-b--fully-manual-installation)
4. [Common Setup After Master Is Up](#4-common-setup-after-master-is-up-both-paths)
5. [Full Implementation Order — What After What](#5-full-implementation-order--what-after-what)
6. [Pipeline-by-Pipeline Reference](#6-pipeline-by-pipeline-reference)
7. [Repository File Map](#7-repository-file-map)
8. [Troubleshooting Index](#8-troubleshooting-index)
9. [Documentation Index](#9-documentation-index)

---

## 1. Two Ways to Get Jenkins Running

| Path | Use When | Time | Detail |
|---|---|---|---|
| **A — Terraform-automated** (`terraform-infra/`) | You want all 4 nodes (Linux master, Windows master, Linux agent, Windows agent) provisioned and bootstrapped in one command | ~5–15 min | [Section 2](#2-path-a--automated-via-terraform-infra) |
| **B — Fully manual** | Classroom/learning goal — install Jenkins yourself on existing/own servers, step by step | ~30–60 min | [Section 3](#3-path-b--fully-manual-installation) |

Both paths converge at the same point: a running Jenkins Master (Linux **or** Windows) with two agents
(`linux-agent`, `windows-agent`) connected. Everything after that (plugins, credentials, pipeline jobs)
is identical regardless of which path you used — see [Section 4](#4-common-setup-after-master-is-up-both-paths).

---

## 2. Path A — Automated via `terraform-infra/`

Provisions **4 EC2 instances** in one `terraform apply`: Linux master, Windows master, Linux agent
(private subnet), Windows agent (private subnet). Full architecture: [docs/07-terraform-pipeline.md](07-terraform-pipeline.md)
(note: that doc covers the **application** infra pipeline (`terraform/`) — the Jenkins infra module
referenced here is `terraform-infra/`, a separate Terraform root).

### 2.1 Prerequisites

- AWS CLI v2 configured with a named profile (`~/.aws/credentials`) with permissions for EC2, VPC, IAM
- Terraform ≥ 1.6 installed locally
- An existing EC2 **key pair** in the target region (default assumed: `sarowar-ostad-mumbai` in `ap-south-1`)
- Your public IP in CIDR form: `curl -s ifconfig.me`

### 2.2 Provision all 4 instances

```bash
cd terraform-infra

terraform init

# Review the plan — override any variable in variables.tf as needed
terraform plan \
  -var="admin_cidr=$(curl -s ifconfig.me)/32" \
  -var="aws_profile=<your-aws-profile>" \
  -var="key_pair_name=<your-key-pair-name>"

terraform apply \
  -var="admin_cidr=$(curl -s ifconfig.me)/32" \
  -var="aws_profile=<your-aws-profile>" \
  -var="key_pair_name=<your-key-pair-name>"
```

> There is no `terraform.tfvars.example` in `terraform-infra/` (unlike `terraform/`) — pass overrides
> with `-var` flags, or create your own `terraform.tfvars` from [variables.tf](../terraform-infra/variables.tf).

### 2.3 Wait for bootstrap, then read the outputs

Terraform prints a `next_steps` output block with every URL/SSH/SSM command needed. Wait:

| Instance | Wait Time |
|---|---|
| Linux master / Linux agent | 3–5 minutes (`user-data` script) |
| Windows master / Windows agent | 10–15 minutes (Chocolatey + Jenkins MSI + Java) |

```bash
terraform output          # reprint all outputs any time
```

### 2.4 Get the initial admin passwords

**Linux master:**
```bash
ssh -i ~/.ssh/<your-key>.pem ubuntu@<LINUX_MASTER_IP> \
  'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'
```

**Windows master** (no SSH — RDP or SSM only):
```bash
aws ssm start-session --target <WINDOWS_MASTER_INSTANCE_ID> --profile <profile> --region ap-south-1
# Inside the session:
Get-Content "C:\ProgramData\Jenkins\.jenkins\secrets\initialAdminPassword"
```
Or retrieve the RDP password: `aws ec2 get-password-data --instance-id <id> --priv-launch-key ~/.ssh/<key>.pem --profile <profile> --region ap-south-1`

Then open `http://<MASTER_IP>:8080` in a browser and complete the Jenkins setup wizard (unlock →
install suggested plugins → create admin user) — same wizard as the manual path, see
[docs/02-jenkins-installation.md § Step 7/8](02-jenkins-installation.md).

### 2.5 Known gap — Docker must be added to the Linux master manually

`terraform-infra/modules/ec2/templates/jenkins-master-linux.sh.tpl` installs Java 21, Jenkins, and
AWS CLI — **it does not install Docker**. `Jenkinsfile.rc` and `Jenkinsfile.deploy-docker` run
`agent { label 'built-in' }` (the master itself) and require Docker Engine there. After the master is
up, install Docker once:

```bash
ssh -i ~/.ssh/<your-key>.pem ubuntu@<LINUX_MASTER_IP>
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

The Linux **agent** template (`jenkins-agent-linux.sh.tpl`) *does* install Docker already — this gap
only affects the master/`built-in` node.

### 2.6 Connect the agents in the Jenkins UI

Terraform prepares the OS-level prerequisites (Java, Docker, workspace directories) on both agents,
but **registering the node in Jenkins is a manual UI step either way** — identical to the manual path:

- Linux agent (SSH launch) → [docs/03-jenkins-agents.md § Agent 1, Part B](03-jenkins-agents.md)
- Windows agent (JNLP + NSSM) → [docs/03-jenkins-agents.md § Agent 2, Part B–G](03-jenkins-agents.md)

Differences from the manual doc when using `terraform-infra`:
- Linux agent SSH user is **`ubuntu`** (not a separate `jenkins` OS user) and root directory is
  `/opt/jenkins-agent` (both already created by the bootstrap script) — use the same
  `key_pair_name` PEM as the SSH credential in Jenkins, not a freshly generated `jenkins_agent_key`.
- Both agents are in the **private subnet** (no public IP) — use `aws ssm start-session` to reach them
  for any manual verification; the Jenkins master reaches them directly over the VPC.

### 2.7 Destroy when done

```bash
cd terraform-infra
terraform destroy -var="admin_cidr=<your-ip>/32" -var="aws_profile=<your-profile>"
```

---

## 3. Path B — Fully Manual Installation

Full step-by-step walkthroughs already exist in this repo — this section is the condensed index.
**Use the linked doc for the complete command set; this table is a quick-reference only.**

### 3.1 Jenkins Master — Linux (Ubuntu 24.04)

Full guide: [docs/02-jenkins-installation.md § Section A](02-jenkins-installation.md)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y fontconfig openjdk-21-jre
sudo install -m 0755 -d /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y jenkins
sudo systemctl enable --now jenkins
sudo ufw allow 22/tcp && sudo ufw allow 8080/tcp && sudo ufw allow 50000/tcp && sudo ufw --force enable
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```
Then browse to `http://<IP>:8080` and complete the setup wizard.

### 3.2 Jenkins Master — Windows Server 2019

Full guide: [docs/02-jenkins-installation.md § Section B](02-jenkins-installation.md)

1. Install JDK 21 (`choco install -y temurin21`, or the Adoptium `.msi` with "Set JAVA_HOME" checked)
2. Download `jenkins.msi` from [jenkins.io/download](https://www.jenkins.io/download/) (LTS)
3. Run the MSI as Administrator → accept defaults → confirm port `8080` → confirm detected `JAVA_HOME`
4. Verify: `Get-Service -Name Jenkins` → `Running`
5. Open firewall: `New-NetFirewallRule -DisplayName "Jenkins Web UI" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow` (repeat for port `50000`)
6. Password: `Get-Content "C:\Program Files\Jenkins\secrets\initialAdminPassword"`
7. Browse to `http://<IP>:8080` and complete the setup wizard

> **Order matters:** install Java **before** the Jenkins MSI, and confirm `JAVA_HOME` is set at the
> machine level — otherwise the Jenkins service fails to register (error 1060). See
> [README.md § Troubleshooting](../README.md#19-troubleshooting) for the fix if this happens.

### 3.3 Jenkins Agent — Linux (SSH launch)

Full guide: [docs/03-jenkins-agents.md § Agent 1](03-jenkins-agents.md)

On the **agent machine**:
```bash
sudo apt update && sudo apt install -y fontconfig openjdk-21-jre
sudo useradd -m -s /bin/bash jenkins
sudo mkdir -p /home/jenkins/workspace && sudo chown -R jenkins:jenkins /home/jenkins/
```
On the **master**, generate a key pair and copy the public key into the agent's
`/home/jenkins/.ssh/authorized_keys` (chmod `700`/`600`), then in Jenkins UI:
`Manage Jenkins → Credentials → Add` (SSH Username with private key) → `Manage Jenkins → Nodes → New Node`
→ Launch method **Launch agents via SSH**, Host = agent IP, Remote root = `/home/jenkins/workspace`,
Label = `linux-agent`.

### 3.4 Jenkins Agent — Windows (JNLP + NSSM Windows Service)

Full guide: [docs/03-jenkins-agents.md § Agent 2](03-jenkins-agents.md)

On the **agent machine**:
```powershell
choco install -y temurin21          # Java 21 JDK, sets JAVA_HOME
New-Item -ItemType Directory -Path "C:\jenkins-agent\workspace" -Force
```
In Jenkins UI: `Manage Jenkins → Nodes → New Node` → Launch method **Launch agent by connecting it to
the controller (JNLP)**, Label = `windows-agent`, Remote root = `C:\jenkins-agent\workspace` → copy the
`-secret` value shown, then on the agent machine:
```powershell
Invoke-WebRequest -Uri "http://<MASTER_IP>:8080/jnlpJars/agent.jar" -OutFile "C:\jenkins-agent\agent.jar"
# Test manually first (Ctrl+C to stop), then install as a service:
nssm install JenkinsAgent "C:\Program Files\Eclipse Adoptium\jdk-21.x.x.x-hotspot\bin\java.exe"
nssm set JenkinsAgent AppParameters "-jar C:\jenkins-agent\agent.jar -url http://<MASTER_IP>:8080/ -secret <SECRET> -name windows-agent -workDir C:\jenkins-agent\workspace"
nssm set JenkinsAgent AppDirectory "C:\jenkins-agent"
nssm set JenkinsAgent Start SERVICE_AUTO_START
nssm start JenkinsAgent
```

---

## 4. Common Setup After Master Is Up (Both Paths)

Do this once per Jenkins master, regardless of Path A or B, before creating any pipeline job.

### 4.1 Install required plugins

`Manage Jenkins → Plugins → Available plugins` — install:

| Plugin | Used By |
|---|---|
| Pipeline | All pipelines |
| Credentials Binding | `Jenkinsfile.rc`, `Jenkinsfile.deploy`, `Jenkinsfile.deploy-docker` (provides `withCredentials`/`sshUserPrivateKey`) |
| Email Extension | All deploy pipelines (`emailext`) |
| Timestamper | All pipelines |
| Docker Pipeline | `Jenkinsfile.rc` (optional — this repo scripts `docker build`/`docker run` via `sh`, so plain Docker Engine + AWS CLI on the node is sufficient) |
| AWS Credentials *(optional)* | Alternative to `usernamePassword` for AWS keys |
| Git Parameter *(optional)* | Branch/tag picker on job forms |

> **Not required / avoid installing unless you also update the Jenkinsfiles accordingly:** SSH Agent,
> Copy Artifact, AnsiColor. Earlier revisions of these pipelines used `sshagent`, `copyArtifacts`, and
> `ansiColor` — all were removed in favor of `withCredentials(sshUserPrivateKey(...))`, direct AWS CLI
> calls, and plain console output, specifically so this repo works with the plugin set above only.

### 4.2 Configure system settings

`Manage Jenkins → System`: set **Jenkins URL** to `http://<IP>:8080/`, set an admin e-mail, and (for
`emailext`) configure SMTP under **Extended E-mail Notification** — see
[README.md § Troubleshooting](../README.md#19-troubleshooting) if using AWS SES.

### 4.3 Add Jenkins credentials (consolidated — all pipelines)

`Manage Jenkins → Credentials → System → Global credentials → Add Credentials`

| ID | Kind | Used By | Value |
|---|---|---|---|
| `ec2-ssh-key` | SSH Username with private key | `Jenkinsfile.deploy`, `Jenkinsfile.deploy-docker` | EC2 target `.pem`, username `ubuntu` |
| `bmi-database-url` | Secret text | `Jenkinsfile.deploy` | `postgresql://bmi_user:PASS@localhost:5432/bmidb` |
| `aws-credentials` | Username with password | `Jenkinsfile.rc`, `Jenkinsfile.deploy-docker` | Username = `AWS_ACCESS_KEY_ID`, Password = `AWS_SECRET_ACCESS_KEY` |
| `bmi-db-password` | Secret text | `Jenkinsfile.deploy-docker` | Strong PostgreSQL password |
| `github-credentials` *(if private repo)* | Username with password | All checkout stages | GitHub username + PAT |

`Jenkinsfile.terraform` needs **no stored AWS credentials** — it uses the IAM role attached to the
Jenkins controller EC2 instance (IMDS).

---

## 5. Full Implementation Order — What After What

This is the master runbook — follow top to bottom on a brand-new environment.

```
 1. Provision Jenkins infrastructure  → Path A (§2) or Path B (§3)
 2. Complete the Jenkins setup wizard on the master(s)                → docs/02
 3. Install plugins + configure system settings                       → §4.1, §4.2
 4. Connect linux-agent and windows-agent nodes                       → docs/03
 5. Add all credentials listed in §4.3                                → §4.3
 6. Create 3 verification pipeline jobs (SL#4) and run them            → docs/04
      bmi-pipeline-master   (Jenkinsfile.master / .masterWindows)
      bmi-pipeline-linux    (Jenkinsfile.linux-agent)
      bmi-pipeline-windows  (Jenkinsfile.windows-agent)
    → confirms all 3 nodes execute pipeline code correctly
 7. Launch an application target EC2 (Ubuntu 24.04) for deployment      → docs/05 § Prerequisites
 8. Create bmi-deploy job → Jenkinsfile.deploy → run it (bare-metal)    → docs/05
      First run = fresh install (Nginx + PM2 + PostgreSQL + migrations)
      Later runs = update existing deployment
 9. Create ECR repos bmi-frontend / bmi-backend (one-time)              → docs/06 § Prerequisites
10. Create bmi-rc-pipeline job → Jenkinsfile.rc → run it                → docs/06
      Builds + pushes Docker images tagged rc-<N> to ECR
11. Create bmi-deploy-docker job → Jenkinsfile.deploy-docker            → docs/06
      Run with RC_BUILD_NUMBER = N from step 10 → deploys via Docker Compose
12. (Optional) Create S3 remote-state bucket + IAM Terraform policy      → docs/07 § Overview
13. Create bmi-terraform-pipeline job → Jenkinsfile.terraform            → docs/07
      ACTION=create/destroy — provisions the separate app-infra EC2 (terraform/)
```

Steps 1–6 are one-time environment setup. Steps 7–11 are the application deployment pipelines (can be
re-run any time code changes). Steps 12–13 are optional/independent infrastructure-as-code practice.

---

## 6. Pipeline-by-Pipeline Reference

| Job Name | Jenkinsfile | Runs On | Doc | Depends On |
|---|---|---|---|---|
| `bmi-pipeline-master` | `Jenkinsfile.master` | `built-in` (Linux master) | [docs/04](04-jenkins-pipelines.md) | Master up |
| `bmi-pipeline-master-windows` | `Jenkinsfile.masterWindows` | `built-in` (Windows master) | [docs/04](04-jenkins-pipelines.md) | Windows master up |
| `bmi-pipeline-linux` | `Jenkinsfile.linux-agent` | `linux-agent` | [docs/04](04-jenkins-pipelines.md) | Linux agent connected |
| `bmi-pipeline-windows` | `Jenkinsfile.windows-agent` | `windows-agent` | [docs/04](04-jenkins-pipelines.md) | Windows agent connected |
| `bmi-deploy` | `Jenkinsfile.deploy` | `built-in` | [docs/05](05-three-tier-deployment.md) | `ec2-ssh-key`, `bmi-database-url` credentials; target EC2 running |
| `bmi-rc-pipeline` | `Jenkinsfile.rc` | `built-in` (needs Docker Engine) | [docs/06](06-docker-deploy.md) | `aws-credentials`; ECR repos exist |
| `bmi-deploy-docker` | `Jenkinsfile.deploy-docker` | `built-in` | [docs/06](06-docker-deploy.md) | `aws-credentials`, `bmi-db-password`, `ec2-ssh-key`; a successful `bmi-rc-pipeline` build number |
| `bmi-terraform-pipeline` | `Jenkinsfile.terraform` | `built-in` | [docs/07](07-terraform-pipeline.md) | IAM role on Jenkins EC2 with Terraform permissions; S3 state bucket |

---

## 7. Repository File Map

| Path | Purpose | Related Doc |
|---|---|---|
| `frontend/`, `backend/` | React SPA + Express API source | [README § 4](../README.md#4-folder-structure) |
| `database/setup-database.sh` | One-shot local PostgreSQL install + migrate | [README § 11](../README.md#11-local-development-setup) |
| `Dockerfile.frontend`, `Dockerfile.backend`, `docker-compose.prod.yml` | Container build/run definitions | [docs/06](06-docker-deploy.md) |
| `jenkins/*.Jenkinsfile*` | All 8 pipeline definitions | [Section 6](#6-pipeline-by-pipeline-reference) |
| `terraform-infra/` | Provisions the 4 Jenkins EC2 nodes themselves | [Section 2](#2-path-a--automated-via-terraform-infra) |
| `terraform/` | Provisions the **application** target infra (used by `Jenkinsfile.terraform`) | [docs/07](07-terraform-pipeline.md) |
| `docs/01` – `07` | Session-by-session (SL#1–SL#7) course guides | [Section 9](#9-documentation-index) |
| `docs/00-master-implementation-guide.md` | This file | — |

---

## 8. Troubleshooting Index

Full troubleshooting write-ups (Windows service error 1060, apt `NO_PUBKEY`, Java version mismatch,
SSM `InvalidInstanceId`, ECR login failures, blank frontend/502) live in
**[README.md § 19 Troubleshooting](../README.md#19-troubleshooting)** — check there first.

---

## 9. Documentation Index

| Doc | Session | Covers |
|---|---|---|
| [docs/00-master-implementation-guide.md](00-master-implementation-guide.md) | SL#0 | This guide — start here |
| [docs/01-jenkins-architecture.md](01-jenkins-architecture.md) | SL#1 | Jenkins concepts, vs GitHub Actions |
| [docs/02-jenkins-installation.md](02-jenkins-installation.md) | SL#2 | Manual Jenkins Master install — Linux & Windows |
| [docs/03-jenkins-agents.md](03-jenkins-agents.md) | SL#3 | Manual Agent setup — Linux (SSH) & Windows (JNLP/NSSM) |
| [docs/04-jenkins-pipelines.md](04-jenkins-pipelines.md) | SL#4 | 3 verification pipelines across master/agents |
| [docs/05-three-tier-deployment.md](05-three-tier-deployment.md) | SL#5 | Bare-metal EC2 deploy (Nginx + PM2 + PostgreSQL) |
| [docs/06-docker-deploy.md](06-docker-deploy.md) | SL#6 | Docker build → ECR → Docker Compose deploy |
| [docs/07-terraform-pipeline.md](07-terraform-pipeline.md) | SL#7 | Terraform IaC pipeline for app infrastructure |
| [README.md](../README.md) | — | Full project reference — architecture, tech stack, env vars, security, troubleshooting |
