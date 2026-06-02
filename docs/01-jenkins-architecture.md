# SL#1 — Jenkins Architecture & Core Concepts

> **Class Context:** You already know GitHub Actions (Module 10), Docker, AWS EC2, and Kubernetes.  
> Every concept in this document is anchored to something you already understand.

---

## 1. What is Jenkins?

Jenkins is an open-source, self-hosted automation server written in Java. It was originally created by **Kohsuke Kawaguchi** at Sun Microsystems in 2005 under the name **Hudson**, and was renamed Jenkins in 2011 after Oracle acquired Sun.

Jenkins automates the repetitive technical work in software delivery — building, testing, and deploying code — so engineers can focus on writing features rather than manually running scripts.

Today Jenkins is maintained by the Jenkins community under the **Continuous Delivery Foundation (CDF)** and is used by **tens of thousands of organisations worldwide**, including Netflix, LinkedIn, and most Fortune 500 companies.

---

## 2. Why Jenkins? — The Problem It Solves

Without CI/CD automation, every code change requires a developer to manually:

1. Pull the latest code
2. Install dependencies
3. Run the test suite
4. Build the application artifacts
5. SSH into a server and deploy
6. Verify the deployment

This is **slow**, **inconsistent**, and **does not scale** across a team. Jenkins automates the entire workflow — triggered automatically by a `git push` — and runs it the same way every single time.

---

## 3. Jenkins vs GitHub Actions

You already know GitHub Actions from Module 10. Here is a direct comparison:

| Feature | GitHub Actions | Jenkins |
|---|---|---|
| **Hosting** | SaaS — hosted by GitHub | Self-hosted on your own infrastructure |
| **Cost** | Free for public repos; limited minutes for private | Free software — you pay for the server only |
| **Config format** | YAML in `.github/workflows/` | Jenkinsfile (Groovy DSL) in repo root |
| **Runners / Agents** | GitHub-managed or self-hosted runners | You fully manage all agent nodes |
| **Plugin ecosystem** | ~20,000 community Actions | ~1,800 plugins at plugins.jenkins.io |
| **Git host coupling** | Tightly coupled to GitHub.com | Works with GitHub, GitLab, Bitbucket, Gitea, or any Git server |
| **Secrets management** | GitHub Secrets (per-repo or org) | Jenkins Credentials Store (encrypted on disk) |
| **Trigger types** | `on: push`, `on: pull_request`, schedule, etc. | Webhook, Poll SCM, Schedule, Manual, upstream job |
| **Enterprise audit** | GitHub Enterprise audit log | Full audit trail, LDAP/SAML integration, role-based access |
| **Multi-platform agents** | Limited (Linux, Windows, macOS GitHub-hosted) | Any OS, any architecture, Docker containers as agents |
| **Best for** | Cloud-native, GitHub-centric, smaller teams | Enterprise, on-prem, complex pipelines, multi-platform, regulated industries |

### When to Choose Jenkins Over GitHub Actions

- Your organisation uses **GitLab, Bitbucket**, or an on-premises Git server
- You need pipelines that span **Linux, Windows, and macOS agents** simultaneously
- You are in a **regulated industry** (banking, healthcare) that requires all CI/CD to run on-premises
- Your build uses **complex custom toolchains** or proprietary build systems
- You need deep integration with enterprise tools: **JIRA, Artifactory, SonarQube, Nexus, Splunk**
- You need **full control** over the build environment with no usage caps

---

## 4. Jenkins Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                     JENKINS CONTROLLER (MASTER)                      │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────────┐ │
│  │  Web UI      │  │  Job Configs │  │  Credentials Store         │ │
│  │  port 8080   │  │  (XML/YAML)  │  │  SSH keys, tokens, secrets │ │
│  └──────────────┘  └──────────────┘  └────────────────────────────┘ │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────────┐ │
│  │  Build Queue │  │  Scheduler   │  │  Plugin Manager            │ │
│  │              │  │  (triggers)  │  │  1,800+ plugins            │ │
│  └──────────────┘  └──────────────┘  └────────────────────────────┘ │
└───────────────────────┬──────────────────────┬───────────────────────┘
                        │                      │
               SSH/JNLP │                      │ SSH/JNLP
                        ▼                      ▼
         ┌──────────────────────┐   ┌──────────────────────┐
         │    LINUX AGENT       │   │   WINDOWS AGENT      │
         │    (Ubuntu 24.04)    │   │   (Windows Server)   │
         │                      │   │                      │
         │  ┌────────────────┐  │   │  ┌────────────────┐  │
         │  │  Executor #1   │  │   │  │  Executor #1   │  │
         │  │  [Workspace A] │  │   │  │  [Workspace A] │  │
         │  └────────────────┘  │   │  └────────────────┘  │
         │  ┌────────────────┐  │   │                      │
         │  │  Executor #2   │  │   │  Label:              │
         │  │  [Workspace B] │  │   │  windows-agent       │
         │  └────────────────┘  │   └──────────────────────┘
         │                      │
         │  Label: linux-agent  │
         └──────────────────────┘
```

### Component Definitions

| Component | What It Does | GitHub Actions Equivalent |
|---|---|---|
| **Controller (Master)** | Orchestrates all builds, hosts the UI, stores all configs and job history | GitHub's CI orchestration layer |
| **Agent (Worker Node)** | A machine that connects to the controller and runs build steps | GitHub Actions Runner |
| **Executor** | A single build thread slot on an agent. One agent can run multiple executors (parallel builds) | A single parallel job slot |
| **Workspace** | A temp directory created per-build on the agent. Deleted or reused after the build | `$GITHUB_WORKSPACE` on a runner |
| **Pipeline** | A Jenkinsfile that defines the full automation workflow | `.github/workflows/deploy.yml` |
| **Stage** | A named logical group of steps (e.g. `Build`, `Test`, `Deploy`) | A Job inside a GitHub Actions Workflow |
| **Step** | A single command or action inside a stage | A `step:` entry inside a job |
| **Node** | Any machine in the Jenkins cluster — controller or agent | Runner machine |
| **Label** | A tag on an agent used to route specific jobs to specific nodes | `runs-on: ubuntu-latest` |

---

## 5. Pipeline Syntax — Declarative vs Scripted

Jenkins supports two pipeline styles. We use **Declarative** throughout this course.

### Declarative Pipeline (Recommended)

```groovy
pipeline {
    agent { label 'linux-agent' }    // where to run

    environment {
        APP_NAME = 'bmi-health-tracker'
        NODE_ENV = 'production'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                sh 'npm install && npm run build'
            }
        }

        stage('Test') {
            steps {
                sh 'npm test'
            }
        }

        stage('Deploy') {
            steps {
                sh './deploy.sh'
            }
        }
    }

    post {
        success { echo 'Pipeline succeeded' }
        failure { echo 'Pipeline failed — check console output' }
        always  { echo 'Pipeline finished' }
    }
}
```

### Side-by-Side: Jenkinsfile vs GitHub Actions YAML

```groovy
// Jenkinsfile
pipeline {
    agent { label 'linux-agent' }
    stages {
        stage('Build') {
            steps {
                sh 'npm install && npm run build'
            }
        }
    }
    post {
        success { emailext to: 'team@example.com', subject: 'Build OK' }
    }
}
```

```yaml
# GitHub Actions equivalent
name: Build
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm install && npm run build
      - if: success()
        uses: dawidd6/action-send-mail@v3
        with:
          to: team@example.com
          subject: Build OK
```

**Same logic. Different syntax. Same outcome.**

---

## 6. Credential Types in Jenkins

Never hardcode secrets in a Jenkinsfile. Use Jenkins Credentials Store:

`Manage Jenkins → Credentials → System → Global credentials → Add Credentials`

| Credential Type | Used For | Example |
|---|---|---|
| `Secret Text` | API tokens, passwords, DB connection strings | `DATABASE_URL`, AWS tokens |
| `SSH Username with private key` | SSH into EC2 servers, Git over SSH | EC2 `.pem` key file |
| `Username with password` | DockerHub login, AWS Access Key + Secret | AWS credentials for ECR |
| `AWS Credentials` | Native AWS credential binding (requires AWS Credentials plugin) | AWS_ACCESS_KEY_ID + SECRET |
| `Certificate` | SSL/TLS client certificates | mTLS |

Use in pipeline with `withCredentials`:

```groovy
withCredentials([string(credentialsId: 'bmi-database-url', variable: 'DATABASE_URL')]) {
    sh 'echo "Connecting to $DATABASE_URL"'  // value is masked in console log
}

// SSH key injection
sshagent(credentials: ['ec2-ssh-key']) {
    sh 'ssh -o StrictHostKeyChecking=no ubuntu@$EC2_HOST "pm2 restart bmi-backend"'
}
```

---

## 7. Essential Plugins for This Course

Install these via `Manage Jenkins → Plugins → Available plugins`:

| Plugin | Purpose |
|---|---|
| **Git** | Clone repositories (usually pre-installed) |
| **Pipeline** | Declarative/Scripted pipeline support |
| **SSH Agent** | Inject SSH private keys into pipeline steps |
| **Email Extension (email-ext)** | Send rich HTML email via AWS SES SMTP |
| **Copy Artifact** | Share build artifacts (e.g. `build-manifest.json`) between pipelines |
| **AWS Credentials** | Native AWS credential type for ECR/S3 |
| **Docker Pipeline** | Use Docker commands natively inside pipelines |
| **Credentials Binding** | `withCredentials` block support |
| **Timestamper** | Adds timestamps to all console output |
| **Build Discarder** | Auto-delete old builds to save disk space |

---

## 8. Jenkins Build Lifecycle

```
Developer runs: git push origin main
        │
        ▼
GitHub sends Webhook → POST http://<JENKINS>:8080/github-webhook/
        │
        ▼
Jenkins Controller receives webhook → reads Jenkinsfile from repo
        │
        ▼
Controller queues the build, finds an available agent matching the label
        │
        ▼
Agent allocates an Executor → creates a fresh Workspace
        │
        ▼
Agent: Checkout → Build → Test → Deploy (stages run in order)
        │
        ├── All stages pass → post { success }
        │       → Archive artifacts, send success email, mark build GREEN
        │
        └── Any stage fails → post { failure }
                → Stop pipeline, send failure email, mark build RED
```

---

## 9. Key Jenkinsfile Directives — Quick Reference

```groovy
pipeline {
    agent { label 'linux-agent' }           // Run on agent with this label
    agent none                              // Declare agent per-stage
    agent { docker { image 'node:20' } }   // Run inside a Docker container

    options {
        timestamps()                        // Add timestamps to console
        timeout(time: 30, unit: 'MINUTES') // Kill build if it runs > 30 min
        buildDiscarder(logRotator(numToKeepStr: '10'))  // Keep last 10 builds
    }

    parameters {
        string(name: 'EC2_HOST', defaultValue: '', description: 'Target server')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: '')
        choice(name: 'ENVIRONMENT', choices: ['staging', 'production'], description: '')
    }

    environment {
        APP_NAME = 'bmi-health-tracker'                      // static value
        DB_URL   = credentials('bmi-database-url')           // from Credentials store
    }

    triggers {
        pollSCM('H/5 * * * *')             // Poll Git repo every 5 minutes
        cron('0 2 * * *')                  // Run at 2am every day
    }

    stages {
        stage('Build') {
            when {
                branch 'main'              // Only run on main branch
            }
            steps {
                sh 'npm install'           // Linux shell command
                bat 'npm install'          // Windows batch command
                echo "Build #${BUILD_NUMBER} running on ${NODE_NAME}"
            }
        }
    }

    post {
        always   { echo 'Runs regardless of result' }
        success  { echo 'Runs only on success' }
        failure  { echo 'Runs only on failure' }
        unstable { echo 'Runs when tests fail but build did not error' }
        changed  { echo 'Runs when result changed from previous build' }
    }
}
```

---

## 10. Built-in Environment Variables

Jenkins injects useful variables into every build:

| Variable | Value | Example |
|---|---|---|
| `BUILD_NUMBER` | Current build number | `42` |
| `BUILD_URL` | Full URL to this build | `http://jenkins:8080/job/bmi/42/` |
| `JOB_NAME` | Name of the job | `bmi-rc-pipeline` |
| `NODE_NAME` | Name of the agent running this build | `linux-agent` |
| `WORKSPACE` | Absolute path to the workspace | `/home/jenkins/workspace/bmi` |
| `GIT_BRANCH` | Branch being built | `origin/main` |
| `GIT_COMMIT` | Full SHA of the commit | `a1b2c3d4...` |

Use them in steps:

```groovy
sh "docker tag bmi-frontend:latest bmi-frontend:rc-${BUILD_NUMBER}"
echo "Running on ${NODE_NAME} — Build ${BUILD_NUMBER} — Branch ${GIT_BRANCH}"
```

---

## Summary

| You already know (GitHub Actions) | Jenkins equivalent |
|---|---|
| `.github/workflows/deploy.yml` | `Jenkinsfile` |
| `on: push` | Webhook trigger |
| `jobs:` | `stages:` |
| `steps:` | `steps:` |
| `runs-on: ubuntu-latest` | `agent { label 'linux-agent' }` |
| `env:` | `environment {}` block |
| GitHub Secrets | Jenkins Credentials Store |
| `if: failure()` | `post { failure {} }` |
| GitHub-hosted runner | Jenkins Controller |
| Self-hosted runner | Jenkins Agent |

Jenkins is not harder than GitHub Actions — it is the same concepts with more power and more responsibility for the infrastructure.
