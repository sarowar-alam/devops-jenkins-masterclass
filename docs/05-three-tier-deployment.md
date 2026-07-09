# SL#5 — Bare-Metal Three-Tier Deployment to AWS EC2

> **App:** BMI Health Tracker (React 18 + Node.js/Express + PostgreSQL 14)  
> **Target:** AWS Ubuntu 24.04 LTS EC2 instance  
> **Pipeline:** `jenkins/Jenkinsfile.deploy`  
> **Strategy:** Smart idempotent deployment — detects fresh vs existing, backs up before every update  
> **Notifications:** AWS SES via EC2 IAM Role — no SMTP credentials needed

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

You need **two** credentials in Jenkins before running the pipeline.

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

> Choose a strong password now and keep it consistent — the pipeline extracts this password from the URL and creates the PostgreSQL user with it on first deploy.

---

## Section A — AWS SES Email Setup (IAM Role Approach)

The pipeline sends HTML emails using the **AWS CLI** on the Jenkins master, authenticated via the **EC2 IAM role** — no SMTP credentials or Jenkins email plugin configuration required.

### A1 — Add SES Permission to the Jenkins EC2 IAM Role

1. Go to the **AWS IAM Console** → **Roles**
2. Find the role attached to your Jenkins master EC2 (e.g. `SSM` or `jenkins-master-ec2-role`)
3. Click **Add permissions** → **Create inline policy**
4. Switch to the **JSON** tab and paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ses:SendEmail", "ses:SendRawEmail"],
      "Resource": "*"
    }
  ]
}
```

5. Name the policy `ses-send-policy` → **Create policy**

> If using Terraform (`terraform-infra/`), this policy is already defined in `modules/iam/main.tf` as `aws_iam_role_policy.ses_send` and applied automatically with `terraform apply`.

### A2 — Verify Sender and Recipient Emails in SES

1. Go to: [https://console.aws.amazon.com/ses/](https://console.aws.amazon.com/ses/)
2. Left menu → `Configuration` → **Verified identities** → **Create identity**
3. Select **Email address**
4. Enter your sender email (the value you'll use for `FROM_EMAIL` parameter, e.g. `sarowar@hotmail.com`)
5. Click **Create identity** → check inbox and click the verification link

> **SES Sandbox Mode:** By default both the FROM and TO addresses must be verified. To send to any unverified address, request production access via `SES Console → Account dashboard → Request production access`.

### A3 — Verify the AWS CLI is Accessible to the Jenkins User

The pipeline runs the `aws ses send-email` command as the `jenkins` system user. Confirm it works:

```bash
# On the Jenkins master EC2
sudo -u jenkins /usr/local/bin/aws --version

# If this fails with "Permission denied", fix with:
sudo chmod -R a+rx /usr/local/aws-cli/
sudo -u jenkins /usr/local/bin/aws --version   # verify
```

> The bootstrap script in `terraform-infra/modules/ec2/templates/jenkins-master-linux.sh.tpl` already includes `chmod -R a+rx /usr/local/aws-cli/` for newly provisioned instances.

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

Click **"Add Parameter"** five times:

| # | Type | Name | Default | Description |
|---|---|---|---|---|
| 1 | String | `EC2_HOST` | *(empty)* | `EC2 Public IP or hostname` |
| 2 | String | `EC2_USER` | `ubuntu` | `SSH user on EC2` |
| 3 | String | `SSH_CREDENTIALS_ID` | `ec2-ssh-key` | `Jenkins Credential ID for EC2 SSH key` |
| 4 | String | `NOTIFY_EMAIL` | *(empty)* | `Email address for deployment notifications` |
| 5 | String | `FROM_EMAIL` | `sarowar@hotmail.com` | `SES verified sender email address` |

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

# PostgreSQL 14 via official PGDG repository
# (Ubuntu 24.04 default repos only ship PG16 — PGDG provides PG14)
apt-get install -y gnupg2 wget
install -d /usr/share/postgresql-common/pgdg
wget -q -O /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    https://www.postgresql.org/media/keys/ACCC4CF8.asc
echo "deb [signed-by=...] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
    | tee /etc/apt/sources.list.d/pgdg.list
apt-get update && apt-get install -y postgresql-14 postgresql-contrib-14
systemctl enable postgresql && systemctl start postgresql

# Clone repository
git clone https://github.com/sarowar-alam/devops-jenkins-masterclass.git \
    /home/ubuntu/bmi-health-tracker

# Database setup (inline — no interactive prompts)
# Password extracted from DATABASE_URL Jenkins credential via Python
DB_PASS=$(python3 -c "from urllib.parse import urlparse; print(urlparse('$DATABASE_URL').password)")
sudo -u postgres psql -c "CREATE USER bmi_user WITH PASSWORD '$DB_PASS';"
sudo -u postgres psql -c "CREATE DATABASE bmidb OWNER bmi_user;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE bmidb TO bmi_user;"
# pg_hba.conf updated for scram-sha-256 password auth

# Run migrations (copied to /tmp — postgres user cannot read /home/ubuntu/)
cp /home/ubuntu/bmi-health-tracker/backend/migrations/001_create_measurements.sql /tmp/
cp /home/ubuntu/bmi-health-tracker/backend/migrations/002_add_measurement_date.sql /tmp/
sudo -u postgres psql -d bmidb -f /tmp/001_create_measurements.sql
sudo -u postgres psql -d bmidb -f /tmp/002_add_measurement_date.sql

# Backend: install dependencies, configure, start with PM2
cd /home/ubuntu/bmi-health-tracker/backend && npm install --omit=dev
# Creates .env with DATABASE_URL, PORT, NODE_ENV, FRONTEND_URL
pm2 start ecosystem.config.js
pm2 save
pm2 startup  # Auto-start PM2 on system boot

# Frontend: build and deploy to Nginx
cd /home/ubuntu/bmi-health-tracker/frontend && npm install && npm run build
cp -r dist/* /var/www/bmi-health-tracker/

# Configure Nginx virtual host
# Writes /etc/nginx/sites-available/bmi-health-tracker
# Proxies /api/* to localhost:3000
nginx -t && systemctl reload nginx

# Create deployment marker
echo "Deployed: $(date) | Build: N | Mode: FRESH" \
    > /home/ubuntu/bmi-health-tracker/.deployed
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
   - `FROM_EMAIL`: `sarowar@hotmail.com` (your SES-verified sender)
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

The pipeline sends HTML emails via `aws ses send-email` using the Jenkins EC2 IAM role. No SMTP plugin or credentials needed.

### Success Email

```
Subject: [SUCCESS] BMI Health Tracker Deployed - Build #42

✔ Deployment Successful — BMI Health Tracker — Build #42

Job         bmi-deploy-pipeline
Build       #42
Mode        FRESH / EXISTS
Target      3.x.x.x
App URL     http://3.x.x.x
Console     http://jenkins:8080/job/bmi-deploy-pipeline/42/console
```

### Failure Email

```
Subject: [FAILED] BMI Health Tracker Deployment Failed - Build #42

✘ Deployment Failed — BMI Health Tracker — Build #42

Job         bmi-deploy-pipeline
Build       #42
Target      3.x.x.x
Console     http://jenkins:8080/job/bmi-deploy-pipeline/42/console
```

### Email Failure Fallback (Console)

If SES is misconfigured or the IAM role lacks `ses:SendEmail`, the pipeline **does not fail**. Instead it prints to console:

```
[WARN] SES email failed — ensure IAM role has ses:SendEmail and FROM_EMAIL is verified in SES. Error: ...
```

The deployment itself is unaffected.

---

## Troubleshooting

### "Permission denied (publickey)" when SSHing to EC2

1. Verify the `ec2-ssh-key` credential in Jenkins contains the correct private key
2. Verify the EC2 instance allows SSH from the Jenkins master's IP (Security Group)
3. Verify the key matches the key pair associated with the EC2 instance
4. Test manually: `ssh -i key.pem ubuntu@<EC2_IP>`

### PostgreSQL 14 not found on Ubuntu 24.04

Ubuntu 24.04 (Noble) default repos only ship PostgreSQL 16. The pipeline adds the official PGDG apt repository automatically to install PG14. If you see `E: Unable to locate package postgresql-14`, verify the PGDG repo was added:

```bash
# On EC2
cat /etc/apt/sources.list.d/pgdg.list
sudo apt-get update && sudo apt-get install -y postgresql-14
```

### "aws: not found" in Jenkins sh step

The Jenkins `sh` step runs as the `jenkins` system user with a restricted PATH. AWS CLI v2 is at `/usr/local/bin/aws` but the `jenkins` user may not have permission to traverse `/usr/local/aws-cli/`. Fix:

```bash
# On the Jenkins master EC2
sudo chmod -R a+rx /usr/local/aws-cli/
sudo -u jenkins /usr/local/bin/aws --version   # verify
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

### SES email fails — "MessageId" not returned

1. Verify the sender email (`FROM_EMAIL`) is verified in SES Console → Verified identities
2. In SES sandbox mode, the recipient (`NOTIFY_EMAIL`) must also be verified
3. Verify the IAM role has `ses:SendEmail` permission:
   ```bash
   # On Jenkins master EC2
   aws iam simulate-principal-policy \
     --policy-source-arn "$(aws sts get-caller-identity --query Arn --output text)" \
     --action-names "ses:SendEmail" \
     --resource-arns "*"
   # Look for "EvalDecision": "allowed"
   ```

---

## Project Lead

**MD Sarowar Alam**<br>
Lead DevOps Engineer, WPP Production

📧 Email: [sarowar@hotmail.com](mailto:sarowar@hotmail.com)<br>
🔗 LinkedIn: https://www.linkedin.com/in/sarowar/

---
