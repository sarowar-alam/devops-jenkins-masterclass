# SL#7 — Jenkins + Terraform: Infrastructure as Code Pipeline

## Overview

This section adds a Jenkins pipeline that provisions and destroys AWS infrastructure using **Terraform**. The pipeline has a single `ACTION` parameter: `create` or `destroy`. A manual approval gate sits between the plan and the apply/destroy, preventing accidental infrastructure changes.

### What Gets Created

```
AWS Account (us-east-1)
└── VPC  10.0.0.0/16
    ├── Availability Zone: us-east-1a
    │
    ├── Public Subnet  10.0.1.0/24
    │   ├── Internet Gateway  → 0.0.0.0/0
    │   └── NAT Gateway (Elastic IP attached)
    │
    └── Private Subnet  10.0.2.0/24
        └── EC2 Instance (Ubuntu 24.04 LTS)
            ├── No public IP, no SSH key pair
            ├── Security Group: no inbound, HTTPS/HTTP outbound
            ├── IAM Role → AmazonSSMManagedInstanceCore
            └── Access: AWS SSM Session Manager only
```

### Why SSM Instead of SSH?

| Feature | SSH (Port 22) | SSM Session Manager |
|---------|--------------|---------------------|
| Requires open port | Yes (22 inbound) | No — uses HTTPS 443 |
| Requires key pair | Yes (.pem file) | No — IAM role |
| Works in private subnet | Only with bastion host | Yes, natively |
| Audit trail | None built-in | Full CloudTrail logs |
| Security exposure | Key file can be lost | Credentials are IAM |

The EC2 is in a **private subnet with no public IP**. SSM Session Manager connects to it via an encrypted HTTPS tunnel through the NAT Gateway → Internet → AWS SSM endpoints. No port 22 is ever opened.

---

## File Structure

```
jenkins/
└── Jenkinsfile.terraform       ← Pipeline definition

terraform/
├── backend.tf                  ← Terraform version + S3 backend declaration
├── variables.tf                ← All input variables with descriptions
├── main.tf                     ← All AWS resources
├── outputs.tf                  ← Displayed after apply; archived as artifact
├── userdata.sh.tpl             ← EC2 first-boot script (SSM agent install)
└── terraform.tfvars.example    ← Copy → terraform.tfvars for local runs
```

---

## Prerequisites

### A — Install Terraform on Jenkins Controller

Run on the Jenkins controller machine (Windows Server 2019):

```powershell
# Option 1: Manual install (recommended for air-gapped / corporate environments)
# Download from: https://developer.hashicorp.com/terraform/install

# 1. Download the Windows amd64 zip
Invoke-WebRequest `
  -Uri "https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_windows_amd64.zip" `
  -OutFile "$env:TEMP\terraform.zip"

# 2. Extract to a directory on the PATH
Expand-Archive -Path "$env:TEMP\terraform.zip" -DestinationPath "C:\tools\terraform" -Force

# 3. Add to system PATH permanently
[Environment]::SetEnvironmentVariable(
  "Path",
  $env:Path + ";C:\tools\terraform",
  [EnvironmentVariableTarget]::Machine
)

# 4. Verify (open a new terminal)
terraform version
```

> **Note:** If the Jenkins controller runs on Ubuntu (Linux), use:
> ```bash
> wget https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip
> unzip terraform_1.8.5_linux_amd64.zip -d /usr/local/bin/
> terraform version
> ```

### B — AWS IAM Permissions for Terraform

The `aws-credentials` Jenkins credential must have an IAM user (or role) with these permissions. Create a policy in IAM → Policies → Create Policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VPCFullAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
        "ec2:DescribeVpcs", "ec2:DescribeVpcAttribute",
        "ec2:CreateSubnet", "ec2:DeleteSubnet",
        "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
        "ec2:DescribeInternetGateways",
        "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:DescribeAddresses",
        "ec2:CreateNatGateway", "ec2:DeleteNatGateway", "ec2:DescribeNatGateways",
        "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
        "ec2:CreateRoute", "ec2:DeleteRoute",
        "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
        "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2InstanceAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances", "ec2:TerminateInstances",
        "ec2:DescribeInstances", "ec2:DescribeInstanceStatus",
        "ec2:DescribeImages", "ec2:DescribeAMIs",
        "ec2:DescribeKeyPairs",
        "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeAccountAttributes"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMRoleAndProfile",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:GetRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
        "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
        "iam:GetInstanceProfile", "iam:PassRole",
        "iam:TagRole", "iam:UntagRole",
        "iam:TagInstanceProfile", "iam:UntagInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformStateBackend",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "s3:ListBucket", "s3:GetBucketVersioning",
        "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": [
        "arn:aws:s3:::your-terraform-state-bucket",
        "arn:aws:s3:::your-terraform-state-bucket/*",
        "arn:aws:dynamodb:us-east-1:*:table/terraform-state-lock"
      ]
    }
  ]
}
```

Attach this policy to the IAM user whose access keys are stored in the `aws-credentials` Jenkins credential.

### C — Create S3 State Bucket and DynamoDB Lock Table (One-Time Setup)

Run these commands **once** before the first pipeline run. These resources persist and must NOT be managed by Terraform itself (bootstrap paradox).

```bash
# Replace 'your-terraform-state-bmi-infra' with a globally unique bucket name
BUCKET_NAME="your-terraform-state-bmi-infra"
REGION="us-east-1"

# 1. Create the S3 bucket
aws s3api create-bucket \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}"

# 2. Enable versioning (allows rollback if state file gets corrupted)
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

# 3. Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 4. Block all public access (important for security)
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# 5. Create the DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}"

echo "State backend setup complete."
echo "  S3 Bucket  : ${BUCKET_NAME}"
echo "  DynamoDB   : terraform-state-lock"
```

---

## Jenkins Setup

### Add Jenkins Credential (if not already added from SL#5/SL#6)

The pipeline reuses the existing `aws-credentials` credential:

1. Jenkins Dashboard → **Manage Jenkins** → **Credentials** → **System** → **Global credentials**
2. **+ Add Credentials**
3. Kind: **Username with password**
4. Username: `<your AWS_ACCESS_KEY_ID>`
5. Password: `<your AWS_SECRET_ACCESS_KEY>`
6. ID: `aws-credentials`
7. Description: `AWS Access Keys for Terraform and ECR`
8. **Create**

### Create the Jenkins Pipeline Job

1. Jenkins Dashboard → **+ New Item**
2. Name: `bmi-terraform-pipeline`
3. Type: **Pipeline**
4. **OK**

**Configuration:**

| Section | Setting |
|---------|---------|
| General | ✅ This project is parameterized (auto-populated from Jenkinsfile) |
| Build Triggers | Manual only (no SCM polling needed) |
| Pipeline → Definition | **Pipeline script from SCM** |
| SCM | **Git** |
| Repository URL | `https://github.com/sarowar-alam/devops-jenkins-masterclass.git` |
| Branch | `*/main` |
| Script Path | `jenkins/Jenkinsfile.terraform` |

5. **Save**

---

## Running the Pipeline

### CREATE — Provision Infrastructure

1. Open `bmi-terraform-pipeline` in Jenkins
2. **Build with Parameters**
3. Set parameters:

| Parameter | Value |
|-----------|-------|
| `ACTION` | `create` |
| `AWS_REGION` | `us-east-1` |
| `ENVIRONMENT` | `dev` |
| `INSTANCE_TYPE` | `t3.micro` |
| `STATE_BUCKET` | `your-terraform-state-bmi-infra` |
| `STATE_KEY` | `bmi-infra/terraform.tfstate` |
| `LOCK_TABLE` | `terraform-state-lock` |
| `NOTIFY_EMAIL` | (optional) |

4. **Build**
5. Watch stages in Stage View:
   - **Checkout** → **Verify Tooling** → **Terraform Init** → **Terraform Plan**
   - Pipeline **pauses at Manual Approval**
6. Review the `plan-output.txt` artifact (listed under Build Artifacts)
7. Click **Approve** in the pipeline UI to apply
8. After **Infrastructure Outputs** stage — note the outputs:

```
ec2_instance_id      = "i-0abc123def456"
ec2_private_ip       = "10.0.2.45"
ssm_connect_command  = "aws ssm start-session --target i-0abc123def456 --region us-east-1"
```

### DESTROY — Tear Down Infrastructure

1. **Build with Parameters** → same settings as create, but:

| Parameter | Value |
|-----------|-------|
| `ACTION` | **destroy** |

2. At the **Manual Approval** stage, read the warning carefully
3. Click **Yes, DESTROY the infrastructure** to proceed
4. All resources (EC2, NAT GW, subnets, VPC, IAM role) are removed
5. The S3 state file and DynamoDB table are **NOT** deleted (they are the backend, not managed by this Terraform config)

---

## Connecting to the EC2 Instance

The EC2 instance has **no public IP and no port 22 open**. Use AWS SSM Session Manager:

### Option 1: AWS CLI

```bash
# Install Session Manager Plugin first (one-time):
# https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

aws ssm start-session \
  --target i-0abc123def456 \
  --region us-east-1
```

This opens an interactive shell directly in your terminal — no SSH key, no bastion host.

### Option 2: AWS Management Console

1. AWS Console → **Systems Manager** → **Session Manager**
2. **Start session**
3. Select the instance → **Start session**
4. A browser-based terminal opens

### Option 3: AWS Console Direct Link

After `terraform apply`, the output `ssm_connect_console_url` provides a direct link.

---

## Architecture Deep Dive

### Why is the NAT Gateway in the Public Subnet?

```
Private EC2 → Private Subnet → Private Route Table → NAT Gateway
NAT Gateway lives in PUBLIC Subnet → Public Route Table → Internet Gateway → Internet
```

NAT Gateways must be placed in a **public subnet** to have a path to the internet (via IGW). The private subnet's default route points to the NAT Gateway, which then masquerades the private IP behind the NAT Gateway's Elastic IP. This allows the EC2 to:
- Register with AWS SSM endpoints (`ssm.us-east-1.amazonaws.com`)
- Download packages via `apt-get`
- Access any AWS service API

### SSM Agent Registration Flow

```
1. EC2 boots → user_data runs → amazon-ssm-agent starts
2. SSM agent → HTTPS 443 → NAT GW → IGW → ssm.us-east-1.amazonaws.com
3. SSM agent authenticates using EC2's IAM instance profile (no credentials in code)
4. Instance registers as managed instance in SSM
5. Developer: aws ssm start-session --target i-xxx
6. AWS validates developer's IAM identity → opens encrypted session
7. Shell session proxied through SSM — never a TCP connection on port 22
```

### Security Group Design

```
Inbound rules:  NONE
                (Private subnet — no public IP, no reason to accept connections)

Outbound rules:
  HTTPS (443) → 0.0.0.0/0   SSM agent, AWS APIs, apt over HTTPS
  HTTP  (80)  → 0.0.0.0/0   apt-get package downloads (Ubuntu mirrors)
```

---

## Terraform State Explained

Terraform tracks what it has created in a **state file** (`terraform.tfstate`). Without it, Terraform cannot know which resources to update or destroy.

```
Jenkins Build #1 (create)         Jenkins Build #2 (destroy)
       │                                    │
       ▼                                    ▼
terraform apply                    terraform destroy
       │                                    │
       ├── writes state ──────────── reads state
       ▼                                    ▼
 S3 bucket/key                       S3 bucket/key
 (persists between builds)           (same file — knows what to delete)
```

**DynamoDB Lock Table:** Prevents two pipeline runs from modifying state simultaneously. If Build #3 starts while Build #2 is running, it fails immediately with a lock error rather than corrupting the state.

---

## Troubleshooting

### `Error: No valid credential sources found`
- Verify `aws-credentials` credential ID matches exactly in Jenkinsfile
- Confirm the IAM user's access keys are active in AWS Console

### `Error acquiring the state lock`
- Another pipeline run is currently executing or crashed holding the lock
- Check DynamoDB `terraform-state-lock` table for an item with the state file key
- To manually release: `aws dynamodb delete-item --table-name terraform-state-lock --key '{"LockID":{"S":"your-bucket/bmi-infra/terraform.tfstate"}}'`

### `Error: error reading S3 bucket...`
- Confirm STATE_BUCKET parameter matches the actual bucket name
- Confirm IAM user has `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on the bucket

### `Error: UnauthorizedOperation` during apply
- Confirm IAM policy includes all permissions from Section B of this guide
- Common missing permission: `iam:PassRole` (required when EC2 assumes an IAM role)

### EC2 not showing in SSM Session Manager
- SSM agent needs 2–5 minutes after first boot to register
- Confirm NAT Gateway is in Active state (`aws ec2 describe-nat-gateways`)
- Check userdata log on the instance (requires SSM to be working... chicken-and-egg)
  - Workaround: temporarily move EC2 to public subnet, SSH in, check `/var/log/user-data.log`, then move back

### `terraform destroy` leaves NAT Gateway in "Deleting" state
- NAT Gateways take 60–90 seconds to delete
- The pipeline will wait automatically — no action needed
- If stuck, check AWS Console → VPC → NAT Gateways

---

## Pipeline Summary

| Stage | Duration | What Happens |
|-------|----------|--------------|
| Checkout | ~10s | Pull latest code from Git |
| Verify Tooling | ~15s | Check Terraform + AWS CLI versions, verify AWS credentials |
| Terraform Init | ~20s | Download AWS provider, connect to S3 backend |
| Terraform Plan | ~30s | Compute resource changes, save binary plan file |
| Manual Approval | User-gated | Human reviews plan, approves or aborts (30-min timeout) |
| Terraform Apply / Destroy | ~3–8 min | Execute the plan (NAT GW creation is the slowest step) |
| Infrastructure Outputs | ~5s | Print and archive EC2 ID + SSM connect command |

---

## Cost Estimate

Resources created by this pipeline and approximate AWS cost:

| Resource | Price (us-east-1) |
|----------|------------------|
| NAT Gateway | ~$0.045/hr + $0.045/GB data |
| Elastic IP (when in use) | $0.005/hr |
| EC2 t3.micro | ~$0.0104/hr |
| EBS gp3 20GB | ~$0.08/GB-month |

**Always run the DESTROY pipeline when the EC2 is not needed** — the NAT Gateway is the most expensive component and incurs costs even when idle.

---

## Project Lead

**MD Sarowar Alam**
Lead DevOps Engineer, WPP Production
📧 Email: [sarowar@hotmail.com](mailto:sarowar@hotmail.com)
🔗 LinkedIn: https://www.linkedin.com/in/sarowar/

---
