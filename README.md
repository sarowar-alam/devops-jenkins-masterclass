# BMI Health Tracker — Jenkins CI/CD Masterclass

A full-stack **BMI & Health Tracking** web application built as a practical project for the **Mastering DevOps** Jenkins course. The project demonstrates a complete DevOps lifecycle: 3-tier application development, bare-metal deployment, Docker containerisation, Amazon ECR image registry, and fully automated Terraform infrastructure provisioning — all orchestrated through Jenkins pipelines.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture Overview](#2-architecture-overview)
3. [Tech Stack](#3-tech-stack)
4. [Folder Structure](#4-folder-structure)
5. [Application Workflow](#5-application-workflow)
6. [Jenkins Infrastructure](#6-jenkins-infrastructure)
7. [CI/CD Pipeline Overview](#7-cicd-pipeline-overview)
8. [Jenkins Pipeline Reference](#8-jenkins-pipeline-reference)
9. [Environment Variables](#9-environment-variables)
10. [Prerequisites](#10-prerequisites)
11. [Local Development Setup](#11-local-development-setup)
12. [Database Setup](#12-database-setup)
13. [Build and Run with Docker](#13-build-and-run-with-docker)
14. [Production Deployment — Bare Metal (SL#5)](#14-production-deployment--bare-metal-sl5)
15. [Production Deployment — Docker (SL#6)](#15-production-deployment--docker-sl6)
16. [Terraform Infrastructure Pipeline (SL#7)](#16-terraform-infrastructure-pipeline-sl7)
17. [Monitoring and Logging](#17-monitoring-and-logging)
18. [Security Practices](#18-security-practices)
19. [Troubleshooting](#19-troubleshooting)
20. [Future Improvements](#20-future-improvements)
21. [Contributing](#21-contributing)
22. [License](#22-license)

---

## 1. Project Overview

**BMI Health Tracker** allows users to record body measurements and automatically calculates:

| Metric | Formula |
|---|---|
| BMI | `weight(kg) / height(m)²` |
| BMI Category | Underweight / Normal / Overweight / Obese |
| BMR | Mifflin-St Jeor equation (sex-adjusted) |
| Daily Calories | BMR × activity multiplier (sedentary → very active) |

Users can log multiple measurements over time and view a **30-day BMI trend chart** rendered using Chart.js.

This application is the hands-on vehicle for a 7-session Jenkins course covering installation, agents, pipelines, bare-metal deployment, Docker deployment, and Terraform infrastructure-as-code.

---

## 2. Architecture Overview

### Application Architecture (3-Tier)

```
┌────────────────────────────────────────────────────────┐
│  Tier 1 — Presentation                                 │
│  React 18 SPA (Vite) served by Nginx on port 80        │
│  All /api/* requests proxied to backend:3000           │
└───────────────────────┬────────────────────────────────┘
                        │ HTTP proxy (Nginx → backend)
┌───────────────────────▼────────────────────────────────┐
│  Tier 2 — Application / API                            │
│  Node.js 20 + Express — port 3000 (internal only)      │
│  REST endpoints: POST /api/measurements                │
│                  GET  /api/measurements                │
│                  GET  /api/measurements/trends         │
│                  GET  /health                          │
└───────────────────────┬────────────────────────────────┘
                        │ pg driver (TCP/5432)
┌───────────────────────▼────────────────────────────────┐
│  Tier 3 — Data                                         │
│  PostgreSQL 14 — port 5432 (internal only)             │
│  Database: bmidb  /  User: bmi_user                    │
│  Table: measurements (with 2 applied migrations)       │
└────────────────────────────────────────────────────────┘
```

### Deployment Modes

| Mode | Description | Pipeline |
|---|---|---|
| **Bare Metal** | Nginx + PM2 + PostgreSQL directly on Ubuntu 24.04 EC2 | `Jenkinsfile.deploy` |
| **Docker Compose** | Three containers (frontend, backend, db) on EC2 | `Jenkinsfile.deploy-docker` |

### Jenkins Infrastructure Architecture

```
AWS ap-south-1 (Mumbai)
├── Public Subnet 10.0.1.0/24
│   ├── Linux Master  (t3.medium) — Jenkins controller on Ubuntu 24.04
│   └── Windows Master (t3.large) — Jenkins controller on Windows Server 2019
│
└── Private Subnet 10.0.2.0/24
    ├── Linux Agent  (t3.small)  — Ubuntu 24.04, SSH launch, Docker + Java 21
    └── Windows Agent (t3.medium) — Windows Server 2019, JNLP launch, Java 21
```

All instances are SSM-managed (no bastion host needed). Masters are internet-facing on port 8080. Agents have no public IPs.

---

## 3. Tech Stack

### Application

| Layer | Technology | Version |
|---|---|---|
| Frontend | React | 18.2 |
| Frontend build | Vite | 5.x |
| HTTP client | Axios | 1.4 |
| Charts | Chart.js + react-chartjs-2 | 4.4 / 5.2 |
| Web server | Nginx (Alpine) | latest |
| Backend | Node.js + Express | 20 / 4.18 |
| Process manager | PM2 (bare-metal mode) | latest |
| Database | PostgreSQL | 14 |
| DB driver | node-postgres (pg) | 8.10 |

### DevOps & Infrastructure

| Tool | Purpose |
|---|---|
| Jenkins LTS 2.492+ | CI/CD orchestration |
| Java 21 (Eclipse Temurin) | Jenkins runtime |
| Docker + Docker Compose | Container build and runtime |
| Amazon ECR | Docker image registry |
| Amazon EC2 | Compute (Ubuntu 24.04 + Windows Server 2019) |
| AWS SSM | Secure shell-less access to all instances |
| Terraform ≥ 1.6 | Infrastructure as Code |
| AWS CLI v2 | ECR authentication, SSM commands |
| Chocolatey | Windows package management |

---

## 4. Folder Structure

```
.
├── frontend/                   # React SPA (Vite)
│   ├── src/
│   │   ├── App.jsx             # Root component, data fetching
│   │   ├── api.js              # Axios instance (baseURL: /api)
│   │   ├── components/
│   │   │   ├── MeasurementForm.jsx
│   │   │   └── TrendChart.jsx
│   │   └── index.css
│   ├── index.html
│   ├── package.json
│   └── vite.config.js          # Dev proxy: /api → localhost:3000
│
├── backend/                    # Node.js / Express API
│   ├── src/
│   │   ├── server.js           # Express app, CORS, health endpoint
│   │   ├── routes.js           # REST endpoints
│   │   ├── calculations.js     # BMI, BMR, calorie formulas
│   │   └── db.js               # PostgreSQL pool (pg)
│   ├── migrations/
│   │   ├── 001_create_measurements.sql
│   │   └── 002_add_measurement_date.sql
│   ├── .env.example            # Required environment variables
│   ├── ecosystem.config.js     # PM2 configuration
│   └── package.json
│
├── database/
│   └── setup-database.sh       # Full PostgreSQL install + migrate script
│
├── nginx/
│   └── nginx-frontend.conf     # SPA routing + /api proxy config
│
├── jenkins/                    # All Jenkins pipeline definitions
│   ├── Jenkinsfile.master       # SL#4 — runs on built-in node
│   ├── Jenkinsfile.linux-agent  # SL#4 — runs on linux-agent
│   ├── Jenkinsfile.windows-agent# SL#4 — runs on windows-agent (bat)
│   ├── Jenkinsfile.deploy       # SL#5 — bare-metal SSH deploy
│   ├── Jenkinsfile.rc           # SL#6 — Docker build + ECR push
│   ├── Jenkinsfile.deploy-docker# SL#6 — Docker Compose deploy
│   └── Jenkinsfile.terraform    # SL#7 — Terraform plan/apply/destroy
│
├── terraform-infra/            # Jenkins infrastructure (4 EC2 instances)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── vpc/                # VPC, subnets, IGW, NAT, route tables
│       ├── security/           # Security groups (master + agent)
│       ├── iam/                # EC2 instance profile + SSM policy
│       └── ec2/
│           ├── main.tf
│           └── templates/
│               ├── jenkins-master-linux.sh.tpl
│               ├── jenkins-master-windows.ps1.tpl
│               ├── jenkins-agent-linux.sh.tpl
│               └── jenkins-agent-windows.ps1.tpl
│
├── terraform/                  # App infrastructure (used by SL#7 pipeline)
│   ├── main.tf
│   ├── backend.tf              # S3 remote state backend
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│
├── docs/                       # Course session guides
│   ├── 01-jenkins-architecture.md
│   ├── 02-jenkins-installation.md
│   ├── 03-jenkins-agents.md
│   ├── 04-jenkins-pipelines.md
│   ├── 05-three-tier-deployment.md
│   ├── 06-docker-deploy.md
│   └── 07-terraform-pipeline.md
│
├── Dockerfile.frontend         # Multi-stage: Node 20 build → Nginx Alpine serve
├── Dockerfile.backend          # Node 20 Alpine, non-root user, dumb-init
├── docker-compose.prod.yml     # Three-service production stack
└── .gitignore
```

---

## 5. Application Workflow

```
User opens browser → Nginx (port 80)
        │
        ├─ GET /          → serves React SPA (index.html)
        ├─ GET /assets/*  → static JS/CSS (cached 1 year)
        └─ ANY /api/*     → proxied to backend container/process (port 3000)
                                    │
                                    ├─ POST /api/measurements
                                    │    Validates input → calculates BMI/BMR/calories
                                    │    → inserts into PostgreSQL → returns record
                                    │
                                    ├─ GET /api/measurements
                                    │    → returns all rows ordered by date DESC
                                    │
                                    ├─ GET /api/measurements/trends
                                    │    → 30-day daily average BMI from PostgreSQL
                                    │
                                    └─ GET /health
                                         → { status: "ok", environment: "production" }
```

### BMI Calculation Logic

| Metric | Formula |
|---|---|
| BMI | `weight_kg / (height_m)²` |
| BMR (male) | `10×weight + 6.25×height − 5×age + 5` |
| BMR (female) | `10×weight + 6.25×height − 5×age − 161` |
| Daily Calories | `BMR × activity_multiplier` |

Activity multipliers: `sedentary=1.2`, `light=1.375`, `moderate=1.55`, `active=1.725`, `very_active=1.9`

---

## 6. Jenkins Infrastructure

The Jenkins infrastructure (4 EC2 instances) is provisioned by Terraform in `terraform-infra/` and bootstrapped via EC2 user data scripts.

### Instances

| Node | OS | Subnet | Access | Purpose |
|---|---|---|---|---|
| Linux Master | Ubuntu 24.04 | Public | SSH + SSM | Jenkins controller, runs all pipelines |
| Windows Master | Windows Server 2019 | Public | SSM + RDP | Jenkins controller (Windows pipelines) |
| Linux Agent | Ubuntu 24.04 | Private (10.0.2.x) | SSM | SSH launch agent, Docker + Java 21 |
| Windows Agent | Windows Server 2019 | Private (10.0.2.x) | SSM | JNLP launch agent, Java 21 |

### Provisioning

```bash
cd terraform-infra

# First time only — copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit: admin_cidr (your IP), key_pair_name

terraform init
terraform plan -var="admin_cidr=$(curl -s ifconfig.me)/32"
terraform apply -var="admin_cidr=$(curl -s ifconfig.me)/32"
```

Wait **3–5 minutes** after `apply` for user data to complete. Outputs include Jenkins URLs, SSH/SSM commands, and password retrieval commands.

### Retrieve Initial Admin Password

**Linux Master (SSH):**
```bash
ssh -i ~/.ssh/sarowar-ostad-mumbai.pem ubuntu@<LINUX_MASTER_IP> \
  'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'
```

**Windows Master (SSM):**
```powershell
aws ssm send-command `
  --instance-id <WINDOWS_MASTER_INSTANCE_ID> `
  --document-name AWS-RunPowerShellScript `
  --parameters "commands=['Get-Content C:\ProgramData\Jenkins\.jenkins\secrets\initialAdminPassword']" `
  --profile sarowar-ostad --region ap-south-1 `
  --query "Command.CommandId" --output text
```

---

## 7. CI/CD Pipeline Overview

The project has **7 Jenkins pipelines** mapped to course sessions (SL = Session Lab):

```
SL#4  Jenkinsfile.master         Environment verification on controller node
SL#4  Jenkinsfile.linux-agent    Environment verification on Linux agent
SL#4  Jenkinsfile.windows-agent  Environment verification on Windows agent
SL#5  Jenkinsfile.deploy         Bare-metal deploy → EC2 (Nginx + PM2 + PostgreSQL)
SL#6  Jenkinsfile.rc             Docker build → push to Amazon ECR
SL#6  Jenkinsfile.deploy-docker  Pull from ECR → deploy via Docker Compose
SL#7  Jenkinsfile.terraform      Terraform plan/apply/destroy with manual approval
```

### Pipeline Flow (SL#5 Bare Metal)

```
Code Push → Checkout → Validate Params → Pre-flight Check
    → Fresh EC2?
        YES → Install Node.js, PostgreSQL, Nginx, PM2, run migrations
        NO  → Backup current deploy → git pull → npm install → restart PM2
    → Health Check → Email Notification
```

### Pipeline Flow (SL#6 Docker)

```
Step 1: bmi-rc-pipeline
  Checkout → ECR Login → Build frontend image → Build backend image
  → Push both images tagged rc-<BUILD_NUMBER> → Archive build-manifest.json

Step 2: bmi-deploy-docker (takes RC_BUILD_NUMBER as parameter)
  Copy Artifact (manifest) → SSH to EC2 → Write .env file
  → docker compose pull → docker compose up -d → Health checks → Email
```

---

## 8. Jenkins Pipeline Reference

### Jenkinsfile.deploy (SL#5 — Bare Metal)

| Parameter | Default | Description |
|---|---|---|
| `EC2_HOST` | _(required)_ | EC2 public IP or hostname |
| `EC2_USER` | `ubuntu` | SSH username |
| `SSH_CREDENTIALS_ID` | `ec2-ssh-key` | Jenkins credential ID for PEM key |
| `NOTIFY_EMAIL` | _(required)_ | Email for deployment notifications |

**Required Jenkins Credentials:**

| ID | Type | Value |
|---|---|---|
| `ec2-ssh-key` | SSH Username with private key | EC2 `.pem` file |
| `bmi-database-url` | Secret text | `postgresql://bmi_user:PASS@localhost:5432/bmidb` |

---

### Jenkinsfile.rc (SL#6 — RC Build)

**Required Jenkins Credentials:**

| ID | Type | Value |
|---|---|---|
| `aws-credentials` | Username with password | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` |

**Required on Jenkins controller:** Docker Engine, AWS CLI v2

Produces images tagged `rc-<BUILD_NUMBER>` and pushes to ECR repos `bmi-frontend` and `bmi-backend`.

---

### Jenkinsfile.deploy-docker (SL#6 — Docker Deploy)

| Parameter | Default | Description |
|---|---|---|
| `RC_BUILD_NUMBER` | _(required)_ | Build number from `bmi-rc-pipeline` |
| `EC2_HOST` | _(required)_ | Target EC2 IP |
| `EC2_USER` | `ubuntu` | SSH username |
| `AWS_REGION` | `us-east-1` | Region where ECR repos live |
| `NOTIFY_EMAIL` | _(required)_ | Notification email |

**Required Jenkins Credentials:**

| ID | Type | Value |
|---|---|---|
| `aws-credentials` | Username with password | AWS access key / secret |
| `bmi-db-password` | Secret text | Strong PostgreSQL password |
| `ec2-ssh-key` | SSH Username with private key | EC2 `.pem` file |

**Required Jenkins Plugin:** Copy Artifact (copies manifest from `bmi-rc-pipeline`)

---

### Jenkinsfile.terraform (SL#7)

| Parameter | Default | Description |
|---|---|---|
| `ACTION` | `create` | `create` or `destroy` |
| `AWS_REGION` | `us-east-1` | Target region |
| `ENVIRONMENT` | `dev` | Resource name label |
| `INSTANCE_TYPE` | `t3.micro` | EC2 instance type |
| `STATE_BUCKET` | _(required)_ | S3 bucket for Terraform remote state |

**Authentication:** Uses EC2 Instance Metadata Service (IMDS). The IAM role attached to the Jenkins EC2 must have Terraform permissions. No AWS keys stored in Jenkins credentials.

Pipeline requires **manual approval** between Plan and Apply/Destroy.

---

## 9. Environment Variables

### Backend (`backend/.env`)

Copy `backend/.env.example` and fill in real values:

```bash
cp backend/.env.example backend/.env
```

| Variable | Example | Description |
|---|---|---|
| `PORT` | `3000` | Port the Express server listens on |
| `DATABASE_URL` | `postgresql://bmi_user:password@localhost:5432/bmidb` | PostgreSQL connection string |
| `NODE_ENV` | `production` | `development` or `production` |
| `FRONTEND_URL` | `http://13.201.87.207` | Allowed CORS origin in production |

### Docker Compose Production (`.env` written at deploy time)

| Variable | Description |
|---|---|
| `FRONTEND_IMAGE` | Full ECR URI, e.g. `123456.dkr.ecr.us-east-1.amazonaws.com/bmi-frontend:rc-42` |
| `BACKEND_IMAGE` | Full ECR URI for backend |
| `DATABASE_URL` | `postgresql://bmi_user:PASS@db:5432/bmidb` |
| `POSTGRES_DB` | `bmidb` |
| `POSTGRES_USER` | `bmi_user` |
| `POSTGRES_PASSWORD` | Strong random password |
| `PORT` | `3000` |
| `NODE_ENV` | `production` |
| `FRONTEND_URL` | `http://<EC2_IP>` |

> **Never commit `.env` files.** They are listed in `.gitignore`. Use Jenkins Credentials Store for all secrets.

---

## 10. Prerequisites

### Local Development

| Tool | Version | Purpose |
|---|---|---|
| Node.js | 20.x LTS | Backend runtime + frontend build |
| npm | 9.x+ | Package management |
| PostgreSQL | 14 | Local database |
| Git | 2.x+ | Version control |

### CI/CD (Jenkins Controller)

| Tool | Version | Purpose |
|---|---|---|
| Java (Eclipse Temurin) | 21 | Jenkins runtime |
| Jenkins LTS | 2.492+ | CI/CD server |
| Docker Engine | 24+ | Image builds (SL#6) |
| AWS CLI v2 | 2.x | ECR authentication, SSM |
| Terraform | ≥ 1.6 | Infrastructure pipeline (SL#7) |

### AWS

- AWS account with permissions for: EC2, VPC, IAM, ECR, SSM, S3
- AWS named profile configured (`~/.aws/config` / `~/.aws/credentials`)
- EC2 key pair (`.pem` file) for SSH access to Linux master

### Jenkins Plugins Required

| Plugin | Used By |
|---|---|
| Pipeline | All pipelines |
| SSH Agent | `Jenkinsfile.deploy`, `Jenkinsfile.deploy-docker` |
| Credentials Binding | `Jenkinsfile.rc`, `Jenkinsfile.deploy-docker` |
| Email Extension | All deploy pipelines (notifications) |
| Copy Artifact | `Jenkinsfile.deploy-docker` |
| AnsiColor | `Jenkinsfile.deploy` |
| Timestamper | All pipelines |

---

## 11. Local Development Setup

### 1 — Clone the repository

```bash
git clone https://github.com/sarowar-alam/devops-jenkins-masterclass.git
cd devops-jenkins-masterclass
```

### 2 — Set up the backend

```bash
cd backend
cp .env.example .env
# Edit .env — update DATABASE_URL with your local PostgreSQL credentials

npm install
```

### 3 — Set up the database

Ensure PostgreSQL 14 is running locally, then:

```bash
# Create user and database
psql -U postgres -c "CREATE USER bmi_user WITH PASSWORD 'localdev';"
psql -U postgres -c "CREATE DATABASE bmidb OWNER bmi_user;"

# Run migrations
psql -U bmi_user -d bmidb -f backend/migrations/001_create_measurements.sql
psql -U bmi_user -d bmidb -f backend/migrations/002_add_measurement_date.sql
```

Or run the full automated setup script (requires `sudo`):

```bash
sudo bash database/setup-database.sh
```

### 4 — Start the backend

```bash
cd backend
npm run dev    # nodemon — auto-restarts on file changes
# API available at http://localhost:3000
```

### 5 — Start the frontend

```bash
cd frontend
npm install
npm run dev
# App available at http://localhost:5173
# Vite proxies /api requests to http://localhost:3000
```

---

## 12. Database Setup

### Schema

The `measurements` table is created by migration `001`:

```sql
CREATE TABLE measurements (
  id               SERIAL PRIMARY KEY,
  weight_kg        NUMERIC(5,2)  NOT NULL CHECK (weight_kg > 0 AND weight_kg < 1000),
  height_cm        NUMERIC(5,2)  NOT NULL CHECK (height_cm > 0 AND height_cm < 300),
  age              INTEGER       NOT NULL CHECK (age > 0 AND age < 150),
  sex              VARCHAR(10)   NOT NULL CHECK (sex IN ('male', 'female')),
  activity_level   VARCHAR(30)   CHECK (activity_level IN ('sedentary','light','moderate','active','very_active')),
  bmi              NUMERIC(4,1)  NOT NULL,
  bmi_category     VARCHAR(30),
  bmr              INTEGER,
  daily_calories   INTEGER,
  measurement_date DATE          NOT NULL DEFAULT CURRENT_DATE,
  created_at       TIMESTAMPTZ   DEFAULT now() NOT NULL
);
```

Indexed on `measurement_date DESC`, `created_at DESC`, and `bmi`.

---

## 13. Build and Run with Docker

### Build images individually

```bash
# Build frontend (from repo root)
docker build -f Dockerfile.frontend -t bmi-frontend:latest .

# Build backend (from repo root)
docker build -f Dockerfile.backend -t bmi-backend:latest .
```

### Run full stack with Docker Compose

Create a `.env` file in the repo root with the required variables (see [Environment Variables](#9-environment-variables)), then:

```bash
docker compose -f docker-compose.prod.yml up -d

# Check status
docker compose -f docker-compose.prod.yml ps

# View logs
docker compose -f docker-compose.prod.yml logs -f

# Stop
docker compose -f docker-compose.prod.yml down
```

The stack starts in dependency order: `db` → `backend` (waits for db health) → `frontend` (waits for backend health).

Access the application at **http://localhost**.

---

## 14. Production Deployment — Bare Metal (SL#5)

This pipeline deploys directly onto an EC2 Ubuntu 24.04 instance using SSH. It installs Nginx, Node.js, PostgreSQL 14, and PM2 on the first run. Subsequent runs back up the current deployment and redeploy.

### One-Time Setup

1. **Launch an EC2 instance** — Ubuntu 24.04, t3.small+, port 22 open to Jenkins master IP, port 80 public
2. **Add credentials to Jenkins:**
   - `ec2-ssh-key` — SSH Username with private key (`.pem` file, username `ubuntu`)
   - `bmi-database-url` — Secret text: `postgresql://bmi_user:YOURPASSWORD@localhost:5432/bmidb`
3. **Create a Pipeline job** in Jenkins pointing to `jenkins/Jenkinsfile.deploy`

### Run the Pipeline

In Jenkins, click **Build with Parameters**:

| Field | Value |
|---|---|
| `EC2_HOST` | EC2 public IP |
| `EC2_USER` | `ubuntu` |
| `SSH_CREDENTIALS_ID` | `ec2-ssh-key` |
| `NOTIFY_EMAIL` | your@email.com |

### What Gets Deployed

```
EC2 Ubuntu 24.04
├── Nginx (port 80)      → serves /var/www/bmi-health-tracker/ + proxies /api
├── PM2 (process: bmi-backend)  → Node.js on port 3000
└── PostgreSQL 14        → bmidb database, bmi_user
```

---

## 15. Production Deployment — Docker (SL#6)

Two pipelines work together:

### Step 1 — Build RC Images (`bmi-rc-pipeline`)

```
Job: bmi-rc-pipeline
  → Builds bmi-frontend:rc-<N>  and  bmi-backend:rc-<N>
  → Pushes to ECR (region: us-east-1)
  → Archives build-manifest.json with image URIs
```

**Prerequisites:**
- ECR repositories `bmi-frontend` and `bmi-backend` exist in your AWS account
- Jenkins credential `aws-credentials` configured
- Docker Engine running on Jenkins controller

```bash
# Create ECR repos (one-time)
aws ecr create-repository --repository-name bmi-frontend --region us-east-1
aws ecr create-repository --repository-name bmi-backend  --region us-east-1
```

### Step 2 — Deploy (`bmi-deploy-docker`)

```
Job: bmi-deploy-docker (parameter: RC_BUILD_NUMBER = N from Step 1)
  → Copies build-manifest.json from bmi-rc-pipeline build N
  → SSHes to EC2
  → Writes .env file with image URIs and DB credentials
  → Runs: docker compose -f docker-compose.prod.yml up -d
  → Verifies health endpoints
  → Sends email notification
```

**Deployed stack on EC2:**

| Container | Image | Port |
|---|---|---|
| `bmi-frontend` | ECR `bmi-frontend:rc-N` | `80:80` (public) |
| `bmi-backend` | ECR `bmi-backend:rc-N` | internal `3000` only |
| `bmi-db` | `postgres:14-alpine` | internal `5432` only |

---

## 16. Terraform Infrastructure Pipeline (SL#7)

### One-Time Setup

```bash
# Create S3 bucket for remote state
aws s3 mb s3://your-tf-state-bucket --region us-east-1
aws s3api put-bucket-versioning --bucket your-tf-state-bucket \
  --versioning-configuration Status=Enabled
```

Attach a Terraform IAM policy to the Jenkins EC2 instance role (see `docs/07-terraform-pipeline.md`).

### Pipeline Stages

```
Validate Parameters → Checkout → Terraform Init (S3 backend)
  → Terraform Plan → ⏸ Manual Approval → Terraform Apply/Destroy
  → Archive output (instance ID + SSM connect command)
```

### Provisioned Resources (ACTION=create)

- VPC `10.0.0.0/16` with 1 AZ
- Public subnet + Internet Gateway
- Private subnet + NAT Gateway
- Security groups, IAM role with `AmazonSSMManagedInstanceCore`
- EC2 Ubuntu 24.04 in private subnet (SSM only)

---

## 17. Monitoring and Logging

### Application Logs (Bare Metal)

| Source | Location | Command |
|---|---|---|
| PM2 combined | `backend/logs/combined.log` | `pm2 logs bmi-backend` |
| PM2 errors | `backend/logs/err.log` | `pm2 logs bmi-backend --err` |
| Nginx access | `/var/log/nginx/access.log` | `sudo tail -f /var/log/nginx/access.log` |
| Nginx errors | `/var/log/nginx/error.log` | `sudo tail -f /var/log/nginx/error.log` |
| PostgreSQL | `/var/log/postgresql/` | `sudo journalctl -u postgresql` |

### Application Logs (Docker)

```bash
docker compose -f docker-compose.prod.yml logs -f
docker logs bmi-backend --tail 100
docker logs bmi-frontend --tail 100
```

Containers use `json-file` driver with rotation: **10 MB max, 3 files**.

### Jenkins Bootstrap Logs

| Instance | Log Location |
|---|---|
| Linux Master/Agent | `sudo tail -f /var/log/user-data.log` |
| Windows Master | `Get-Content C:\jenkins-bootstrap.log -Tail 50` |
| Windows Agent | `Get-Content C:\jenkins-agent-bootstrap.log -Tail 50` |

### Health Endpoints

| Endpoint | Expected Response |
|---|---|
| `GET /health` | `{"status":"ok","environment":"production"}` |
| `GET /api/measurements` | `{"rows":[...]}` |

---

## 18. Security Practices

| Practice | Implementation |
|---|---|
| Non-root containers | Backend runs as `nodeuser` (UID 1001); never as root |
| Minimal base images | `node:20-alpine`, `nginx:alpine` — minimal attack surface |
| No secrets in images | All credentials injected at runtime via environment variables |
| CORS restriction | Production CORS limited to `FRONTEND_URL`; dev allows `localhost:5173` only |
| No SSH on agents | Agents in private subnet, accessed only via AWS SSM (no inbound SG rules) |
| No hardcoded credentials | All secrets in Jenkins Credentials Store, never in Jenkinsfiles |
| `.gitignore` | `.env`, `terraform.tfvars`, `*.tfstate`, `*.tfplan` excluded from git |
| DB constraint validation | PostgreSQL `CHECK` constraints prevent invalid data at the database level |
| Input validation | Express routes validate required fields and positive-number ranges |
| Security group principle | Agents: no inbound internet rules; masters: SSH/RDP restricted to `admin_cidr` |
| Signal handling | `dumb-init` in backend container — proper PID 1 signal forwarding |
| Container healthchecks | All three `docker-compose.prod.yml` services have `healthcheck` with dependency ordering |

---

## 19. Troubleshooting

### Jenkins not accessible after `terraform apply`

User data takes **3–5 min** (Linux) or **10–15 min** (Windows) to complete.

```bash
# Linux
ssh -i ~/.ssh/key.pem ubuntu@<IP> 'sudo tail -30 /var/log/user-data.log'

# Windows (SSM session)
aws ssm start-session --target <INSTANCE_ID> --profile sarowar-ostad --region ap-south-1
# Then: Get-Content C:\jenkins-bootstrap.log -Tail 50
```

### Windows master Jenkins service not found (error 1060)

`JAVA_HOME` was not set in the active session when the Jenkins MSI ran. Fix via SSM:

```powershell
$javaHome = (Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory | Where-Object { $_.Name -like '*21*' } | Select-Object -First 1).FullName
[System.Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, 'Machine')
$env:JAVA_HOME = $javaHome; $env:Path = "$javaHome\bin;$env:Path"
choco install -y jenkins --force
Start-Service Jenkins
```

The `jenkins-master-windows.ps1.tpl` template was fixed to set `JAVA_HOME` before the MSI runs on all future instances.

### `NO_PUBKEY 7198F4B714ABFC68` on Linux apt update

Jenkins rotated their signing key in December 2025. Fix:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update && sudo apt install -y jenkins
```

All Linux templates already use the 2026 key.

### Jenkins fails to start — requires Java 21

Jenkins LTS 2.492+ dropped Java 17 support:

```bash
# Linux
sudo apt install -y openjdk-21-jre

# Windows
choco install -y temurin21
```

### SSM send-command returns `InvalidInstanceId`

SSM agent needs 1–2 minutes after boot to register:

```powershell
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=<INSTANCE_ID>" \
  --profile sarowar-ostad --region ap-south-1
# Wait until PingStatus = "Online"
```

### Docker pipeline: ECR login fails

Ensure ECR repos exist and the `aws-credentials` IAM user has ECR permissions:

```bash
aws ecr create-repository --repository-name bmi-frontend --region us-east-1
aws ecr create-repository --repository-name bmi-backend  --region us-east-1
```

### Frontend blank page / API 502 errors

In Docker Compose mode, Nginx proxies `/api` to `http://backend:3000`. Verify backend is healthy:

```bash
docker compose -f docker-compose.prod.yml ps
docker logs bmi-backend --tail 20
```

---

## 20. Future Improvements

- **HTTPS / TLS** — ALB with ACM certificate, or Certbot/Let's Encrypt on Nginx
- **Database backups** — Scheduled `pg_dump` to S3 with lifecycle retention
- **User authentication** — JWT-based login to isolate measurements per user
- **Kubernetes** — Migrate Docker Compose stack to EKS with Helm charts
- **DynamoDB state locking** — Add to the SL#7 Terraform S3 backend for concurrent safety
- **Slack/Teams notifications** — Webhook-based alerts alongside email
- **SonarQube gate** — Code quality check in the RC pipeline before ECR push
- **Blue/green deployment** — Two Compose stacks + Nginx upstream switch for zero-downtime
- **Prometheus metrics** — Expose `/metrics` endpoint and scrape with Grafana

---

## 21. Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Use conventional commit messages: `feat:`, `fix:`, `docs:`, `refactor:`
4. Test locally before pushing
5. Open a Pull Request against `main`

**Never commit:** `.env`, `terraform.tfvars`, `*.tfstate`, `*.tfplan`, or any file containing real credentials or IP addresses.

---

## 22. License

This project is created for educational purposes as part of the **Mastering DevOps — Jenkins for DevOps Engineers** course at [Ostad](https://ostad.app).

The source code is provided for learning and reference. All AWS infrastructure is provisioned under your own account and subject to AWS pricing. Run `terraform destroy` when not in use to avoid charges.

---

*Last updated: June 2026 — Jenkins LTS 2.555.2 · Java 21 (Eclipse Temurin) · Jenkins signing key: jenkins.io-2026.key*

---

## Project Lead

**MD Sarowar Alam**
Lead DevOps Engineer, WPP Production
📧 Email: [sarowar@hotmail.com](mailto:sarowar@hotmail.com)
🔗 LinkedIn: https://www.linkedin.com/in/sarowar/

---
