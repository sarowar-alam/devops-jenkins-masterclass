# SL#5 — Bare-Metal Three-Tier Deployment to AWS EC2

> **App:** BMI Health Tracker (React 18 + Node.js/Express + PostgreSQL 14)  
> **Target:** AWS Ubuntu 24.04 LTS EC2 instance  
> **Pipeline:** `jenkins/Jenkinsfile.deploy`  
> **Strategy:** Smart idempotent deployment — detects fresh vs existing, backs up before every update  
> **Notifications:** AWS SES SMTP email via Jenkins Email Extension Plugin

---

## Architecture: What Gets Deployed

```
AWS EC2 — Ubuntu 24.04 LTS
├── Nginx (port 80)
│   ├── Serves  → /var/www/bmi-health-tracker/  (React dist/)
│   └── Proxies /api/* → localhost:3000
│
├── Node.js Backend (port 3000, managed by PM2)
│   └── /home/ubuntu/bmi-health-tracker/backend/
│
└── PostgreSQL 14 (port 5432, local socket)
    └── Database: bmidb / User: bmi_user
```

---

## Prerequisites

### 1 — EC2 Instance Setup

Launch an EC2 instance with these settings:

| Setting | Value |
|---|---|
| **AMI** | Ubuntu 24.04 LTS (64-bit x86) |
| **Instance type** | `t3.small` or larger |
| **Storage** | 20 GB gp3 |
| **Key pair** | Create or select an existing `.pem` key pair |

**Security Group inbound rules:**

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | Your IP (or Jenkins master IP) | SSH access |
| 80 | TCP | 0.0.0.0/0 | Frontend (Nginx) |
| 443 | TCP | 0.0.0.0/0 | HTTPS (optional) |

> **Important:** Only the Jenkins master needs SSH access (port 22) to the EC2 instance. Port 80 is public-facing.

---

### 2 — Jenkins Credentials Setup

You need three credentials in Jenkins before running the pipeline.

#### Credential 1 — EC2 SSH Private Key

1. `Manage Jenkins` → `Credentials` → `System` → `Global credentials` → `Add Credentials`
2. Fill in:
   - **Kind:** `SSH Username with private key`
   - **ID:** `ec2-ssh-key` *(must match Jenkinsfile.deploy)*
   - **Description:** `EC2 Ubuntu Production Server SSH Key`
   - **Username:** `ubuntu`
   - **Private Key:** `Enter directly` → paste the contents of your `.pem` key file

> Open your `.pem` file in a text editor, copy everything including `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----`, paste it here.

#### Credential 2 — Database URL

1. `Add Credentials`
2. Fill in:
   - **Kind:** `Secret text`
   - **ID:** `bmi-database-url` *(must match Jenkinsfile.deploy)*
   - **Description:** `BMI App PostgreSQL Connection String`
   - **Secret:** `postgresql://bmi_user:YourStrongPassword123!@localhost:5432/bmidb`

> Choose a strong password. This exact password will be used when `setup-database.sh` creates the PostgreSQL user.

#### Credential 3 — Default Notification Email

1. `Manage Jenkins` → `System` → **Default Recipients** field
   - Enter your email address here
   - Or set per-pipeline via the `NOTIFY_EMAIL` parameter

---

## Section A — AWS SES Setup for Email Notifications

Jenkins uses AWS Simple Email Service (SES) as the SMTP relay for all deployment notifications. Follow these steps exactly.

### A1 — Verify Your Sender Email in SES

1. Go to: [https://console.aws.amazon.com/ses/](https://console.aws.amazon.com/ses/)
2. In the left menu: `Configuration` → `Verified identities`
3. Click **Create identity**
4. Select **Email address**
5. Enter the email you want to send FROM (e.g. `jenkins@yourdomain.com` or your personal email)
6. Click **Create identity**
7. **Check your inbox** and click the verification link in the email from AWS

> **SES Sandbox Mode:** By default, SES accounts are in sandbox mode. You can only send TO verified email addresses. To send to any email, request production access (next step).

### A2 — Request SES Production Access (Remove Sandbox)

If you want to send emails to non-verified addresses (required for production):

1. SES Console → `Account dashboard`
2. Click **"Request production access"**
3. Fill in:
   - **Mail type:** Transactional
   - **Website URL:** Your project URL or GitHub repo URL
   - **Use case description:** "Jenkins CI/CD notification emails for DevOps automation pipelines"
   - **Additional contacts:** your email
4. Click **Submit** — AWS reviews in 24 hours

> **For the classroom:** Verify both your sender AND recipient email in SES sandbox. That is sufficient to test.

### A3 — Create SES SMTP Credentials

SES uses special SMTP credentials derived from IAM. Do **not** use your regular AWS Access Key here.

1. SES Console → `Account dashboard` → scroll to `Simple Mail Transfer Protocol (SMTP) settings`
2. Click **"Create SMTP credentials"**
3. An IAM user name is pre-filled (e.g. `ses-smtp-user.20260602`) — accept it or rename
4. Click **Create user**
5. **DOWNLOAD the credentials file** — this is the only time you can see the SMTP password

The file contains:
```
IAM User Name: ses-smtp-user.20260602
SMTP Username: AKIA...
SMTP Password: BHDs...
```

> Store these securely. If you lose the password, you must create new SMTP credentials.

**SES SMTP Endpoint details:**

| Setting | Value |
|---|---|
| SMTP Server | `email-smtp.us-east-1.amazonaws.com` |
| Port | `587` (STARTTLS — recommended) |
| Encryption | STARTTLS |

> Replace `us-east-1` with your actual AWS region if different.

### A4 — Configure Jenkins Email Extension Plugin

1. `Manage Jenkins` → `Plugins` → `Available` → Search **"Email Extension"** → Install
2. After installation: `Manage Jenkins` → `System`
3. Scroll to **"Extended E-mail Notification"** section:

| Field | Value |
|---|---|
| **SMTP server** | `email-smtp.us-east-1.amazonaws.com` |
| **SMTP Port** | `587` |
| **Credentials** | Click `Add` → Kind: `Username with password` → Username = SES SMTP Username, Password = SES SMTP Password → ID: `ses-smtp-creds` |
| **Use SSL** | ☐ Unchecked |
| **Use TLS** | ✅ Checked (STARTTLS) |
| **Default user e-mail suffix** | `@yourdomain.com` (optional) |
| **Default Recipients** | `yourname@gmail.com` (your verified recipient) |
| **Default Content Type** | `HTML (text/html)` |

4. Click **"Test configuration by sending test e-mail"**
   - Enter your verified email → click **Test configuration**
   - You should receive a test email within 1–2 minutes

5. Click **Save**

---

## Section B — Create the Deployment Pipeline Job

### B1 — Create the Job

1. Jenkins Dashboard → **New Item**
2. **Item name:** `bmi-deploy-pipeline`
3. Select **Pipeline** → click **OK**

### B2 — Configure General Settings

| Field | Value |
|---|---|
| **Description** | Bare-metal deploy of BMI Health Tracker to AWS EC2 (PM2 + Nginx) |
| **This project is parameterised** | ✅ Checked |
| **Discard old builds** | ✅ Checked — Max 20 builds |

### B3 — Add Pipeline Parameters

Click **"Add Parameter"** four times:

| # | Type | Name | Default | Description |
|---|---|---|---|---|
| 1 | String | `EC2_HOST` | *(empty)* | `EC2 Public IP or hostname` |
| 2 | String | `EC2_USER` | `ubuntu` | `SSH user on EC2` |
| 3 | String | `SSH_CREDENTIALS_ID` | `ec2-ssh-key` | `Jenkins Credential ID for EC2 SSH key` |
| 4 | String | `NOTIFY_EMAIL` | *(empty)* | `Email address for deployment notifications` |

### B4 — Configure the Pipeline

Scroll to the **Pipeline** section:

| Field | Value |
|---|---|
| **Definition** | `Pipeline script from SCM` |
| **SCM** | `Git` |
| **Repository URL** | `https://github.com/sarowar-alam/devops-jenkins-masterclass.git` |
| **Credentials** | `github-credentials` (or none for public repo) |
| **Branch Specifier** | `*/main` |
| **Script Path** | `jenkins/Jenkinsfile.deploy` |

Click **Save**.

---

## Section C — What the Pipeline Does

### Pipeline Stages

```
┌─────────────────┐
│   1. Checkout   │ ← Clone repo on Jenkins master
└────────┬────────┘
         │
┌────────▼────────────────┐
│  2. Validate Parameters │ ← Fail fast if EC2_HOST or NOTIFY_EMAIL empty
└────────┬────────────────┘
         │
┌────────▼──────────────────────────┐
│  3. Pre-flight Check (SSH to EC2) │ ← Check .deployed marker file
│     EXISTS → env.DEPLOY_MODE = EXISTS
│     FRESH  → env.DEPLOY_MODE = FRESH
└────────┬──────────────────────────┘
         │
    ┌────┴────┐
    │         │
  FRESH    EXISTS
    │         │
┌───▼───┐ ┌──▼────────────────────────┐
│  4A.  │ │  4B. Update Existing      │
│ Full  │ │  - Backup to /backups/    │
│Install│ │    bmi-YYYYMMDD-HHMMSS/   │
│       │ │  - git pull origin main   │
│- git  │ │  - npm install --omit=dev │
│- node │ │  - npm run build          │
│- psql │ │  - copy dist/ to Nginx    │
│- nginx│ │  - pm2 restart bmi-backend│
│- pm2  │ │  - nginx reload           │
│- clone│ └──────────────┬────────────┘
│- mig  │                │
│- build│                │
│- nginx│                │
└───┬───┘                │
    └─────────┬──────────┘
              │
┌─────────────▼──────────────────────┐
│  5. Health Check                   │
│  curl http://localhost (frontend)  │
│  curl http://localhost:3000/api/.. │
│  pm2 status                        │
└─────────────┬──────────────────────┘
              │
┌─────────────▼──────────────────────┐
│  post { success } → SES Email      │
│  post { failure } → SES Email      │
│  post { always  } → Console log    │
│  [WARN] if email fails → console   │
└────────────────────────────────────┘
```

### Fresh Install: What Gets Installed

On a brand new EC2 instance, the pipeline installs everything from scratch:

```bash
# System packages
apt-get install -y git curl

# Node.js 20.x via NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Nginx web server
apt-get install -y nginx
systemctl enable nginx

# PM2 process manager
npm install -g pm2

# PostgreSQL 14
apt-get install -y postgresql-14 postgresql-contrib-14
systemctl enable postgresql
systemctl start postgresql

# Clone repository
git clone https://github.com/sarowar-alam/devops-jenkins-masterclass.git /home/ubuntu/bmi-health-tracker

# Run database setup script (creates user, database, tables)
bash /home/ubuntu/bmi-health-tracker/database/setup-database.sh

# Backend: install dependencies, configure, start with PM2
cd backend && npm install --omit=dev
# Creates .env with DATABASE_URL, PORT, NODE_ENV
pm2 start ecosystem.config.js
pm2 save
pm2 startup  # Auto-start PM2 on system boot

# Frontend: build and deploy to Nginx
cd frontend && npm install && npm run build
cp -r dist/* /var/www/bmi-health-tracker/

# Configure Nginx virtual host
# Writes /etc/nginx/sites-available/bmi-health-tracker
# Proxies /api/* to localhost:3000
nginx -t && systemctl reload nginx

# Create deployment marker
echo "Deployed: $(date) | Build: N" > /home/ubuntu/bmi-health-tracker/.deployed
```

### Update Deploy: What Gets Backed Up

On subsequent runs, the pipeline creates a timestamped backup before updating:

```
/home/ubuntu/backups/
└── bmi-20260602-143022/
    ├── backend-src/        ← copy of backend/src/
    ├── frontend-src/       ← copy of frontend/src/
    └── dist-backup/        ← copy of current /var/www/bmi-health-tracker/
```

Then it pulls the latest code and redeploys.

---

## Section D — Running the Pipeline

### First Run (Fresh EC2)

1. Jenkins Dashboard → `bmi-deploy-pipeline` → **Build with Parameters**
2. Fill in parameters:
   - `EC2_HOST`: `18.x.x.x` (your EC2 public IP)
   - `EC2_USER`: `ubuntu`
   - `SSH_CREDENTIALS_ID`: `ec2-ssh-key`
   - `NOTIFY_EMAIL`: `yourname@gmail.com`
3. Click **Build**
4. Watch Console Output — full install takes 5–10 minutes

**After success:**
- Open `http://<EC2_IP>` in browser → BMI Health Tracker UI loads
- Open `http://<EC2_IP>/api/measurements` → returns `[]` (empty array JSON)
- Check your email for the success notification

### Second Run (Update)

1. Make a code change: edit a file, commit, push to GitHub
2. `bmi-deploy-pipeline` → **Build with Parameters** → same parameters → **Build**
3. Pipeline detects `.deployed` marker → runs update path
4. Check backup exists: SSH to EC2 → `ls /home/ubuntu/backups/`

### Verifying the Deployment on EC2

```bash
# SSH into your EC2 instance
ssh -i your-key.pem ubuntu@<EC2_IP>

# Check Nginx status
sudo systemctl status nginx

# Check PM2
pm2 status
pm2 logs bmi-backend

# Check PostgreSQL
sudo systemctl status postgresql

# Test frontend
curl -s http://localhost | head -20

# Test backend API
curl -s http://localhost:3000/api/measurements

# View deployment history
cat /home/ubuntu/bmi-health-tracker/.deployed

# List backups
ls -la /home/ubuntu/backups/
```

---

## Section E — Rollback

If a deployment breaks the application, roll back to the latest backup:

```bash
ssh -i your-key.pem ubuntu@<EC2_IP>

# List available backups
ls -la /home/ubuntu/backups/

# Pick the backup you want (e.g. bmi-20260602-130000)
BACKUP=/home/ubuntu/backups/bmi-20260602-130000

# Restore backend source
sudo cp -r $BACKUP/backend-src/* /home/ubuntu/bmi-health-tracker/backend/src/

# Restore frontend dist
sudo cp -r $BACKUP/dist-backup/* /var/www/bmi-health-tracker/

# Restart services
pm2 restart bmi-backend
sudo systemctl reload nginx

# Verify
curl -s http://localhost | head -5
curl -s http://localhost:3000/api/measurements
```

---

## Email Notification Format

### Success Email

```
Subject: [SUCCESS] BMI Health Tracker — Deployed | Build #42

Deployment Successful

Job         bmi-deploy-pipeline
Build #     42
Mode        FRESH / EXISTS
Target      ubuntu@18.x.x.x
App URL     http://18.x.x.x
API URL     http://18.x.x.x/api/measurements
Console     http://jenkins:8080/job/bmi-deploy-pipeline/42/console
```

### Email Failure Fallback (Console)

If SES is misconfigured or unreachable, the pipeline **does not fail**. Instead it prints to console:

```
[WARN] Email notification failed — check SES SMTP config in Manage Jenkins > System > Extended E-mail Notification. Error: ...
```

The deployment itself is unaffected.

---

## Troubleshooting

### "Permission denied (publickey)" when SSHing to EC2

1. Verify the `ec2-ssh-key` credential in Jenkins contains the correct private key
2. Verify the EC2 instance allows SSH from the Jenkins master's IP (Security Group)
3. Verify the key matches the key pair associated with the EC2 instance
4. Test manually: `ssh -i key.pem ubuntu@<EC2_IP>`

### "setup-database.sh: Permission denied"

```bash
# On EC2: make the script executable
chmod +x /home/ubuntu/bmi-health-tracker/database/setup-database.sh
```

### "pm2: command not found" during update

PM2 was installed but not in PATH for the `ubuntu` user:

```bash
# On EC2
npm install -g pm2
export PATH="$PATH:/usr/local/bin"
echo 'export PATH="$PATH:/usr/local/bin"' >> ~/.bashrc
```

### Nginx shows "502 Bad Gateway"

The backend is not running. Check:

```bash
pm2 status
pm2 logs bmi-backend
# Look for connection errors to PostgreSQL
```

### Frontend loads but `/api` returns 404

Nginx proxy config was not applied correctly:

```bash
sudo cat /etc/nginx/sites-available/bmi-health-tracker
sudo nginx -t
sudo systemctl reload nginx
```

---

## Project Lead

**MD Sarowar Alam**
Lead DevOps Engineer, WPP Production
📧 Email: [sarowar@hotmail.com](mailto:sarowar@hotmail.com)
🔗 LinkedIn: https://www.linkedin.com/in/sarowar/

---
