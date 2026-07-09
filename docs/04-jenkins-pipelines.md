# SL#4 — Jenkins Pipelines: Master, Linux Agent, Windows Agent

> **Prerequisites:** Windows Jenkins Master running (SL#2) + both agents connected (SL#3).  
> You will create **three separate Pipeline jobs**, each using a different Jenkinsfile from this repo,  
> each running on a different node to demonstrate multi-node execution.

---

## Overview

| Pipeline Job Name | Jenkinsfile in Repo | Target Node | Shell |
|---|---|---|---|
| `bmi-pipeline-master` | `jenkins/Jenkinsfile.master` | Controller (built-in) | `sh` (Linux) |
| `bmi-pipeline-linux` | `jenkins/Jenkinsfile.linux-agent` | linux-agent (Ubuntu) | `sh` (Linux) |
| `bmi-pipeline-windows` | `jenkins/Jenkinsfile.windows-agent` | windows-agent (Windows) | `bat` (Windows) |

Each pipeline has 4 stages:
1. **Checkout** — clones the repository
2. **Verify Environment** — prints OS info, hostname, Java version, build details
3. **List Files** — shows the project structure
4. **Build Report** — summarises which node/OS executed the build

---

## Step 1 — Verify Agent Availability

Before creating jobs, confirm all nodes are connected:

`Manage Jenkins` → `Nodes`

| Node | Expected Status |
|---|---|
| Built-In Node | ✅ Online |
| linux-agent | ✅ Online |
| windows-agent | ✅ Online |

If any agent shows offline, refer to the troubleshooting section in `03-jenkins-agents.md`.

---

## Step 2 — Configure GitHub Credentials (Once, Used by All 3 Jobs)

If the repository is private, add credentials once and all three jobs will reuse them.

1. `Manage Jenkins` → `Credentials` → `System` → `Global credentials` → `Add Credentials`
2. Fill in:
   - **Kind:** `Username with password`
   - **ID:** `github-credentials`
   - **Username:** `sarowar-alam` (your GitHub username)
   - **Password:** Your GitHub Personal Access Token (PAT)
   - **Description:** `GitHub PAT for repo access`
3. Click **Create**

> **Create a GitHub PAT:**  
> GitHub → Settings → Developer Settings → Personal access tokens (classic) → Generate new token  
> Scope: `repo` (full control of private repositories)

For a **public repository**, no credentials are needed.

---

## Step 3 — Create Pipeline Job: `bmi-pipeline-master`

This job runs **on the Jenkins controller itself** using `jenkins/Jenkinsfile.master`.

### 3.1 Create the Job

1. Jenkins Dashboard → **New Item**
2. **Item name:** `bmi-pipeline-master`
3. Select **Pipeline** → click **OK**

### 3.2 Configure General Settings

| Field | Value |
|---|---|
| **Description** | BMI Health Tracker pipeline running on the Jenkins Master (built-in node) |
| **Discard old builds** | ✅ Checked |
| **Max # of builds to keep** | `10` |

### 3.3 Configure Build Triggers (Optional)

To trigger automatically on `git push`:

1. Check **"GitHub hook trigger for GITScm polling"**
2. In your GitHub repo: Settings → Webhooks → Add webhook
   - Payload URL: `http://<MASTER_IP>:8080/github-webhook/`
   - Content type: `application/json`
   - Events: Just the push event
   - Click **Add webhook**

### 3.4 Configure the Pipeline

Scroll to the **Pipeline** section at the bottom:

| Field | Value |
|---|---|
| **Definition** | `Pipeline script from SCM` |
| **SCM** | `Git` |
| **Repository URL** | `https://github.com/sarowar-alam/devops-jenkins-masterclass.git` |
| **Credentials** | `github-credentials` (or none for public repo) |
| **Branch Specifier** | `*/main` |
| **Script Path** | `jenkins/Jenkinsfile.master` |

> **Script Path** is the key difference between the three jobs — it tells Jenkins which Jenkinsfile to use.

Click **Save**.

### 3.5 Run the Job

1. Click **"Build Now"**
2. In **Build History**, click the build number (e.g. `#1`)
3. Click **Console Output**

Expected output includes:
```
Running on: MASTER (built-in)
Hostname     : <your-master-hostname>
OS           : Linux ... (Ubuntu controller)
Node         : Built-In Node
```

---

## Step 4 — Create Pipeline Job: `bmi-pipeline-linux`

This job runs on the **Linux Ubuntu agent** using `jenkins/Jenkinsfile.linux-agent`.

### 4.1 Create the Job

1. Jenkins Dashboard → **New Item**
2. **Item name:** `bmi-pipeline-linux`
3. Select **Pipeline** → click **OK**

### 4.2 Configure General Settings

| Field | Value |
|---|---|
| **Description** | BMI Health Tracker pipeline running on the Linux (Ubuntu 24.04) agent |
| **Discard old builds** | ✅ Checked — Max 10 builds |

### 4.3 Configure the Pipeline

| Field | Value |
|---|---|
| **Definition** | `Pipeline script from SCM` |
| **SCM** | `Git` |
| **Repository URL** | `https://github.com/sarowar-alam/devops-jenkins-masterclass.git` |
| **Credentials** | `github-credentials` (or none for public repo) |
| **Branch Specifier** | `*/main` |
| **Script Path** | `jenkins/Jenkinsfile.linux-agent` |

Click **Save**.

### 4.4 Run the Job

1. Click **"Build Now"**
2. Click **Console Output**

Expected output includes:
```
Running on: LINUX AGENT
Hostname     : <agent-hostname>
OS           : Linux ... (Ubuntu 24.04)
Node         : linux-agent
```

---

## Step 5 — Create Pipeline Job: `bmi-pipeline-windows`

This job runs on the **Windows agent** using `jenkins/Jenkinsfile.windows-agent`.

### 5.1 Create the Job

1. Jenkins Dashboard → **New Item**
2. **Item name:** `bmi-pipeline-windows`
3. Select **Pipeline** → click **OK**

### 5.2 Configure General Settings

| Field | Value |
|---|---|
| **Description** | BMI Health Tracker pipeline running on the Windows Server agent |
| **Discard old builds** | ✅ Checked — Max 10 builds |

### 5.3 Configure the Pipeline

| Field | Value |
|---|---|
| **Definition** | `Pipeline script from SCM` |
| **SCM** | `Git` |
| **Repository URL** | `https://github.com/sarowar-alam/devops-jenkins-masterclass.git` |
| **Credentials** | `github-credentials` (or none for public repo) |
| **Branch Specifier** | `*/main` |
| **Script Path** | `jenkins/Jenkinsfile.windows-agent` |

Click **Save**.

### 5.4 Run the Job

1. Click **"Build Now"**
2. Click **Console Output**

Expected output includes:
```
Running on: WINDOWS AGENT
Hostname : <windows-agent-computername>
OS Version: Microsoft Windows Server 2019 ...
Node     : windows-agent
```

---

## Step 6 — Run All Three Jobs and Compare

After all three jobs have run at least once, go to the Jenkins Dashboard.  
You will see all three jobs listed with green checkmarks.

**What to observe and compare:**

| | `bmi-pipeline-master` | `bmi-pipeline-linux` | `bmi-pipeline-windows` |
|---|---|---|---|
| **Node** | Built-In Node | linux-agent | windows-agent |
| **OS** | Linux (Ubuntu) | Linux (Ubuntu) | Windows Server |
| **Shell used** | `sh` | `sh` | `bat` |
| **List command** | `ls -la` | `ls -la` | `dir` |
| **Workspace path** | `/var/lib/jenkins/workspace/...` | `/home/jenkins/workspace/...` | `C:\jenkins-agent\workspace\...` |

This demonstrates the **core value of multi-node Jenkins** — the same repository, same pipeline structure, but each job runs in an isolated environment on a different machine.

---

## Jenkinsfile Content Reference

### `jenkins/Jenkinsfile.master`

Key settings:
```groovy
agent { label 'built-in' }          // Targets the Jenkins controller
// Uses sh '' for all shell commands
```

### `jenkins/Jenkinsfile.linux-agent`

Key settings:
```groovy
agent { label 'linux-agent' }       // Targets the Ubuntu 24.04 agent
// Uses sh '' for all shell commands
```

### `jenkins/Jenkinsfile.windows-agent`

Key settings:
```groovy
agent { label 'windows-agent' }     // Targets the Windows Server agent
// Uses bat ''' for all Windows batch commands
// Uses %VARIABLE% syntax instead of $VARIABLE
```

---

## Understanding the `agent { label }` Directive

The `label` directive in the `agent` block is how Jenkins routes a build to a specific machine:

```groovy
// Routes to the built-in controller node
pipeline {
    agent { label 'built-in' }
    ...
}

// Routes to any node labelled 'linux-agent'
pipeline {
    agent { label 'linux-agent' }
    ...
}

// Routes to any node labelled 'windows-agent'
pipeline {
    agent { label 'windows-agent' }
    ...
}
```

The label must match exactly what you configured in `Manage Jenkins → Nodes → <node-name> → Labels`.

If no agent with the matching label is available (offline or busy), the build **waits in queue** until one becomes available.

---

## Build Parameters (Optional Enhancement)

You can add parameters to any pipeline to make it interactive:

Navigate to the job → **Configure** → scroll to **"This project is parameterised"** → **Add Parameter**

```groovy
parameters {
    string(
        name: 'TARGET_BRANCH',
        defaultValue: 'main',
        description: 'Git branch to build'
    )
    booleanParam(
        name: 'VERBOSE',
        defaultValue: false,
        description: 'Print verbose output'
    )
}
```

When you click **"Build with Parameters"** instead of "Build Now", Jenkins prompts you to fill in the values before starting the build.

---

## Troubleshooting

### Job stays in queue — "Waiting for next available executor"

1. Check that the target agent is online: `Manage Jenkins` → `Nodes`
2. Check the label in the Jenkinsfile matches the label on the node
3. If the node is online but busy, increase executors: Node config → Number of executors → increase to 3

### "ERROR: script not found in workspace"

The `Script Path` in the job configuration points to a file that doesn't exist in the repo. Verify:
- The Jenkinsfile exists at the exact path (e.g. `jenkins/Jenkinsfile.master`)
- The branch is correct (`*/main` not `*/master`)
- The repo cloned successfully (check "Checkout" stage in console)

### Windows agent — `bat` step fails with "The system cannot find the file specified"

The `bat` step runs `cmd.exe`. If the command references a file, use full paths:

```groovy
bat 'dir C:\\jenkins-agent\\workspace'   // Use \\ for backslash in Groovy strings
```

### "No such DSL method 'sh'" on Windows agent

The `sh` step is Linux-only. Windows pipelines must use `bat`. That is why we have separate Jenkinsfiles — `Jenkinsfile.windows-agent` uses `bat` exclusively.

---

## Next Steps

With three working pipeline jobs verified, you are ready for:

- **SL#5 — `bmi-pipeline-deploy`:** Full bare-metal deployment pipeline to AWS EC2
- **SL#6 — `bmi-rc-pipeline` + `bmi-deploy-docker`:** Docker + ECR build and deploy pipelines

---

## Project Lead

**MD Sarowar Alam**<br>
Lead DevOps Engineer, WPP Production

📧 Email: [sarowar@hotmail.com](mailto:sarowar@hotmail.com)<br>
🔗 LinkedIn: https://www.linkedin.com/in/sarowar/

---
