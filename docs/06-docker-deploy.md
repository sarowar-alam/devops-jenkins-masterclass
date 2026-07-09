# SL#6 — Docker Containerisation & ECR Deploy Pipeline

> **App:** BMI Health Tracker (React 18 + Node.js/Express + PostgreSQL 14)  
> **Strategy:** Two-pipeline model — RC Build pipeline → Docker Deploy pipeline  
> **Registry:** Amazon ECR (Elastic Container Registry)  
> **Target:** AWS Ubuntu 24.04 LTS EC2 (Docker Compose deployment)  
> **Difference from SL#5:** App runs in Docker containers instead of directly on the host OS

---

## Two-Pipeline Model

```
┌─────────────────────────────────────────────────────┐
│  PIPELINE 1: bmi-rc-pipeline  (Jenkinsfile.rc)      │
│                                                     │
│  Checkout → ECR Login → Create ECR Repos            │
│  → Build Frontend Image → Build Backend Image       │
│  → Tag: rc-<BUILD_NUMBER> → Push both to ECR        │
│  → Archive build-manifest.json                      │
│  → Email notification                               │
└─────────────────────┬───────────────────────────────┘
                      │ build-manifest.json (artifact)
                      │ RC_BUILD_NUMBER (parameter)
┌─────────────────────▼──────────────────────────────────────┐
│  PIPELINE 2: bmi-deploy-docker (Jenkinsfile.deploy-docker) │
│                                                            │
│  Fetch Manifest → Prepare EC2 (Docker + AWS CLI)           │
│  → SCP docker-compose.prod.yml to EC2                      │
│  → Write .env → ECR login on EC2                           │
│  → Rolling update OR fresh deploy                          │
│  → Health check → Email notification                       │
└────────────────────────────────────────────────────────────┘
```

---

## Container Architecture

```
EC2 Ubuntu 24.04
└── Docker Compose
    ├── frontend (nginx:alpine)
    │   ├── Image built from: Dockerfile.frontend
    │   ├── Port: 0.0.0.0:80 → 80
    │   ├── Serves React SPA from /usr/share/nginx/html
    │   └── Proxies /api/* → http://backend:3000
    │
    ├── backend (node:20-alpine)
    │   ├── Image built from: Dockerfile.backend
    │   ├── Port: 3000 (internal, not exposed to host)
    │   └── Connects to db:5432 via Docker network
    │
    └── db (postgres:14-alpine)
        ├── Port: 5432 (internal only)
        ├── Init scripts: backend/migrations/*.sql via docker-entrypoint-initdb.d/
        └── Volume: db_data (persistent across container restarts)
```

---

## Prerequisites

### 1 — IAM Permissions for ECR

Your AWS user/role needs these permissions. Navigate to:  
`IAM Console` → `Users` → your user → `Add permissions` → `Attach policies directly`

**Option A (easy — classroom):** Attach `AmazonEC2ContainerRegistryFullAccess`

**Option B (production — least privilege):** Create a custom policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:CreateRepository",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages"
      ],
      "Resource": "arn:aws:ecr:<REGION>:<ACCOUNT_ID>:repository/bmi-*"
    }
  ]
}
```

### 2 — Create AWS Access Keys

You need an **Access Key ID** and **Secret Access Key** for Jenkins to call AWS APIs.

1. `IAM Console` → `Users` → your user → `Security credentials` tab
2. Under **Access keys** → click **Create access key**
3. Use case: `Application running outside AWS`
4. Click **Create access key**
5. **Download the `.csv` file** — this is the only time you can see the secret

---

## Section A — Jenkins Credentials Setup

You need these credentials configured before running either pipeline.

### A1 — AWS Credentials

1. `Manage Jenkins` → `Credentials` → `System` → `Global credentials` → `Add Credentials`
2. Fill in:
   - **Kind:** `Username with password`
   - **ID:** `aws-credentials` *(must match Jenkinsfile.rc)*
   - **Description:** `AWS Access Key for ECR`
   - **Username:** `AKIA...` (your AWS Access Key ID)
   - **Password:** `...` (your AWS Secret Access Key)
3. Click **Create**

### A2 — Database Password

1. `Add Credentials`
2. Fill in:
   - **Kind:** `Secret text`
   - **ID:** `bmi-db-password` *(must match Jenkinsfile.deploy-docker)*
   - **Description:** `BMI App PostgreSQL Password`
   - **Secret:** `YourStrongPassword123!` (choose a strong password)
3. Click **Create**

### A3 — EC2 SSH Key

1. `Add Credentials`
2. Fill in:
   - **Kind:** `SSH Username with private key`
   - **ID:** `ec2-ssh-key`
   - **Description:** `EC2 Ubuntu Production Server SSH Key`
   - **Username:** `ubuntu`
   - **Private Key:** `Enter directly` → paste your `.pem` contents
3. Click **Create**

---

## Section B — Install Required Jenkins Plugins

`Manage Jenkins` → `Plugins` → `Available plugins`

| Plugin | Why Needed |
|---|---|
| **Copy Artifact** | Deploy pipeline copies `build-manifest.json` from RC pipeline |
| **AWS Credentials** | Native AWS credential binding (optional but recommended) |
| **Docker Pipeline** | `docker.build()`, `docker.withRegistry()` support |
| **SSH Agent** | `sshagent { }` block for EC2 SSH |
| **Email Extension** | SES email notifications (install steps in `05-three-tier-deployment.md`) |

---

## Section C — Create the ECR Repositories Manually (Optional)

The RC pipeline creates the repos automatically if they don't exist. But you can also create them manually:

```bash
# Using AWS CLI (install if needed: sudo apt install awscli or pip install awscli)
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1

# Create frontend repo
aws ecr create-repository \
  --repository-name bmi-frontend \
  --image-scanning-configuration scanOnPush=true \
  --region us-east-1

# Create backend repo
aws ecr create-repository \
  --repository-name bmi-backend \
  --image-scanning-configuration scanOnPush=true \
  --region us-east-1

# Verify
aws ecr describe-repositories --region us-east-1
```

---

## Section D — Create Pipeline Job 1: `bmi-rc-pipeline`

This pipeline **builds Docker images and pushes them to ECR**.

### D1 — Create the Job

1. Jenkins Dashboard → **New Item**
2. **Item name:** `bmi-rc-pipeline`
3. Select **Pipeline** → click **OK**

### D2 — Configure General Settings

| Field | Value |
|---|---|
| **Description** | RC Build — Builds and pushes BMI Docker images to ECR |
| **Discard old builds** | ✅ Max 20 builds (ECR images are the real archive) |
| **This project is parameterised** | ✅ (optional — useful for specifying AWS region) |

### D3 — Configure the Pipeline

| Field | Value |
|---|---|
| **Definition** | `Pipeline script from SCM` |
| **SCM** | `Git` |
| **Repository URL** | `https://github.com/sarowar-alam/devops-jenkins-masterclass.git` |
| **Branch Specifier** | `*/main` |
| **Script Path** | `jenkins/Jenkinsfile.rc` |

Click **Save**.

### D4 — Run the RC Pipeline

1. Click **Build Now**
2. Watch Console Output

**Expected output per stage:**
```
[Checkout]              → Repository cloned
[ECR Login]             → Login Succeeded
[Create ECR Repos]      → ECR repo ready: bmi-frontend
                          ECR repo ready: bmi-backend
[Build Frontend Image]  → Successfully built <id>
                          Frontend image built: bmi-frontend:rc-1
[Build Backend Image]   → Successfully built <id>
                          Backend image built: bmi-backend:rc-1
[Push to ECR]           → Pushed: 123456789.dkr.ecr.us-east-1.amazonaws.com/bmi-frontend:rc-1
                          Pushed: 123456789.dkr.ecr.us-east-1.amazonaws.com/bmi-backend:rc-1
                          Build manifest created
[Cleanup Local Images]  → Local images cleaned up
```

3. In **Build Artifacts**: download `build-manifest.json` to see the image URIs

**Verify in ECR Console:**
- AWS Console → ECR → Repositories
- You should see `bmi-frontend` and `bmi-backend` repositories
- Each with an image tagged `rc-1`

---

## Section E — Create Pipeline Job 2: `bmi-deploy-docker`

This pipeline **pulls images from ECR and deploys them to EC2 using Docker Compose**.

### E1 — Create the Job

1. Jenkins Dashboard → **New Item**
2. **Item name:** `bmi-deploy-docker`
3. Select **Pipeline** → click **OK**

### E2 — Configure General Settings

| Field | Value |
|---|---|
| **Description** | Docker Deploy — Pulls RC images from ECR and deploys to AWS EC2 |
| **This project is parameterised** | ✅ Checked |
| **Discard old builds** | ✅ Max 20 builds |

### E3 — Add Pipeline Parameters

| # | Type | Name | Default | Description |
|---|---|---|---|---|
| 1 | String | `RC_BUILD_NUMBER` | *(empty)* | `RC pipeline build number (e.g. 42)` |
| 2 | String | `EC2_HOST` | *(empty)* | `EC2 Public IP or hostname` |
| 3 | String | `EC2_USER` | `ubuntu` | `SSH user on EC2` |
| 4 | String | `SSH_CREDENTIALS_ID` | `ec2-ssh-key` | `Jenkins Credential ID for EC2 SSH key` |
| 5 | String | `NOTIFY_EMAIL` | *(empty)* | `Email for deployment notifications` |
| 6 | String | `AWS_REGION` | `us-east-1` | `AWS region where ECR repos reside` |

### E4 — Configure the Pipeline

| Field | Value |
|---|---|
| **Definition** | `Pipeline script from SCM` |
| **SCM** | `Git` |
| **Repository URL** | `https://github.com/sarowar-alam/devops-jenkins-masterclass.git` |
| **Branch Specifier** | `*/main` |
| **Script Path** | `jenkins/Jenkinsfile.deploy-docker` |

Click **Save**.

### E5 — Run the Deploy Pipeline

1. Click **Build with Parameters**
2. Fill in:
   - `RC_BUILD_NUMBER`: `1` (the build number from `bmi-rc-pipeline` run in D4)
   - `EC2_HOST`: `18.x.x.x` (your EC2 public IP)
   - `EC2_USER`: `ubuntu`
   - `SSH_CREDENTIALS_ID`: `ec2-ssh-key`
   - `NOTIFY_EMAIL`: `yourname@gmail.com`
   - `AWS_REGION`: `us-east-1`
3. Click **Build**

---

## Section F — What the Deploy Pipeline Does

### Stage: Prepare EC2

On a fresh EC2 instance, the pipeline installs:

```bash
# Docker CE (latest stable)
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker ubuntu
systemctl enable --now docker

# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
```

This step is idempotent — it checks if Docker/AWS CLI are already installed before attempting to install.

### Stage: Deploy to EC2

```bash
# Write .env file with image URIs and credentials
# Transfer docker-compose.prod.yml to EC2

# ECR login on EC2
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ECR_REGISTRY>

# Check if containers are already running
RUNNING=$(docker compose -f docker-compose.prod.yml ps --services --filter status=running | wc -l)

if [ "$RUNNING" -gt "0" ]; then
    # Rolling update — zero-downtime
    docker compose -f docker-compose.prod.yml pull
    docker compose -f docker-compose.prod.yml up -d --remove-orphans
else
    # Fresh deployment
    docker compose -f docker-compose.prod.yml pull
    docker compose -f docker-compose.prod.yml up -d
fi
```

### Stage: Health Check

```bash
# Wait 10 seconds for containers to stabilise
sleep 10

# Check container status
docker compose -f /home/ubuntu/bmi-docker/docker-compose.prod.yml ps

# Frontend
curl -sf http://localhost   && echo "[OK] Frontend responding on port 80"

# Backend API
curl -sf http://localhost:3000/api/measurements && echo "[OK] Backend API responding"
```

---

## Section G — Rollback Strategy

Since all RC images are retained in ECR by tag, rolling back is simply re-deploying an older RC:

```
# To rollback to RC build #38 (previous stable):
bmi-deploy-docker → Build with Parameters
  → RC_BUILD_NUMBER: 38
  → (all other parameters same)
  → Build
```

The deploy pipeline pulls `rc-38` images from ECR and redeploys. No data is lost — the PostgreSQL `db_data` volume is never touched during rollback.

**To check available image tags in ECR:**

```bash
aws ecr list-images \
  --repository-name bmi-frontend \
  --region us-east-1 \
  --query 'imageIds[*].imageTag' \
  --output table
```

---

## Section H — EC2 Docker Management Commands

After deployment, SSH into EC2 to manage containers:

```bash
ssh -i your-key.pem ubuntu@<EC2_IP>

# View running containers
docker compose -f /home/ubuntu/bmi-docker/docker-compose.prod.yml ps

# View logs
docker compose -f /home/ubuntu/bmi-docker/docker-compose.prod.yml logs -f

# View specific service logs
docker compose -f /home/ubuntu/bmi-docker/docker-compose.prod.yml logs -f backend

# Stop all containers
docker compose -f /home/ubuntu/bmi-docker/docker-compose.prod.yml down

# Stop and remove volumes (CAUTION: deletes database data)
docker compose -f /home/ubuntu/bmi-docker/docker-compose.prod.yml down -v

# Restart a single service
docker compose -f /home/ubuntu/bmi-docker/docker-compose.prod.yml restart backend

# Check resource usage
docker stats
```

---

## Section I — Build Manifest Format

The RC pipeline archives a `build-manifest.json` file. The deploy pipeline reads it via the **Copy Artifact** plugin:

```json
{
  "buildNumber": "42",
  "imageTag": "rc-42",
  "timestamp": "2026-06-02T14:30:00Z",
  "gitCommit": "a1b2c3d",
  "gitBranch": "origin/main",
  "images": {
    "frontend": "123456789.dkr.ecr.us-east-1.amazonaws.com/bmi-frontend:rc-42",
    "backend":  "123456789.dkr.ecr.us-east-1.amazonaws.com/bmi-backend:rc-42"
  },
  "ecrRegistry": "123456789.dkr.ecr.us-east-1.amazonaws.com",
  "awsRegion": "us-east-1"
}
```

---

## Comparing SL#5 (Bare-Metal) vs SL#6 (Docker)

| Aspect | SL#5 Bare-Metal (PM2 + Nginx) | SL#6 Docker (Compose + ECR) |
|---|---|---|
| **Runtime** | Directly on host OS | Inside Docker containers |
| **Database** | PostgreSQL installed on host | PostgreSQL in container with volume |
| **Frontend serving** | Nginx on host | Nginx inside container |
| **Process management** | PM2 | Docker Compose |
| **Rollback** | Restore from `/home/ubuntu/backups/` | Re-deploy older `rc-N` tag from ECR |
| **Environment isolation** | None (shares host packages) | Full — each service in its own container |
| **Portability** | Tied to Ubuntu 24.04 | Runs on any host with Docker |
| **Build step** | Runs on EC2 during deploy | Runs on Jenkins, image pushed to ECR |
| **Production readiness** | Good for simple apps | Preferred for microservices / scale |
| **Debugging** | `pm2 logs`, `journalctl` | `docker logs`, `docker exec -it` |

---

## Troubleshooting

### "denied: Your authorization token has expired"

ECR tokens expire after 12 hours. Re-run the RC or deploy pipeline — it re-authenticates automatically.

### "Error response from daemon: pull access denied"

1. The ECR login on EC2 may have failed. Check that `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` were correctly set in the pipeline
2. Verify the ECR repository exists: `aws ecr describe-repositories --region us-east-1`
3. Verify the image tag exists: `aws ecr list-images --repository-name bmi-frontend`

### "no space left on device" on EC2

Docker images accumulate. Clean up old images:

```bash
# Remove dangling images
docker image prune -f

# Remove all unused images
docker image prune -a -f

# Full system prune (removes stopped containers, unused volumes, networks)
docker system prune -f
```

### Frontend loads but API calls return 502

The `backend` container is not reachable from the `frontend` container. Check:

```bash
# Verify all containers are on the same Docker network
docker network inspect bmi-docker_bmi-network

# Verify backend container is running
docker compose -f /home/ubuntu/bmi-docker/docker-compose.prod.yml ps

# Check backend logs
docker compose -f /home/ubuntu/bmi-docker/docker-compose.prod.yml logs backend
```

The `nginx/nginx-frontend.conf` must proxy to `http://backend:3000` (Docker service name), not `http://localhost:3000`.

### Copy Artifact fails: "no such build"

Verify:
1. The RC pipeline job is named exactly `bmi-rc-pipeline` (matches `projectName` in `copyArtifacts`)
2. The `RC_BUILD_NUMBER` you entered exists in that pipeline
3. The Copy Artifact plugin is installed: `Manage Jenkins` → `Plugins` → `Installed`
4. The RC pipeline archived `build-manifest.json` (check its build artifacts)

---

## Project Lead

**MD Sarowar Alam**<br>
Lead DevOps Engineer, WPP Production

📧 Email: [sarowar@hotmail.com](mailto:sarowar@hotmail.com)<br>
🔗 LinkedIn: https://www.linkedin.com/in/sarowar/

---
