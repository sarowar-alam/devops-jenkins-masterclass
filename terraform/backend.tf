# ============================================================
# Terraform Remote State Backend — Amazon S3 + DynamoDB
#
# WHY: Jenkins pipelines may run on different agents or clean
# workspaces on every build. If Terraform state were kept
# locally in the Jenkins workspace, it would be LOST between
# builds — making Terraform unable to track or destroy what
# it created.
#
# S3 backend solves this:
#   - State file persists in S3 across all Jenkins builds
#   - DynamoDB table prevents two pipeline runs from modifying
#     state simultaneously (state locking)
#
# HOW TO SET UP (one-time, before first pipeline run):
#
#   Step 1 — Create the S3 bucket (AWS CLI):
#     aws s3api create-bucket \
#       --bucket your-terraform-state-bmi-infra \
#       --region us-east-1
#     aws s3api put-bucket-versioning \
#       --bucket your-terraform-state-bmi-infra \
#       --versioning-configuration Status=Enabled
#     aws s3api put-bucket-encryption \
#       --bucket your-terraform-state-bmi-infra \
#       --server-side-encryption-configuration \
#         '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#
#   Step 2 — Create the DynamoDB table for state locking:
#     aws dynamodb create-table \
#       --table-name terraform-state-lock \
#       --attribute-definitions AttributeName=LockID,AttributeType=S \
#       --key-schema AttributeName=LockID,KeyType=HASH \
#       --billing-mode PAY_PER_REQUEST \
#       --region us-east-1
#
# The actual bucket name, key, and region are passed via
# -backend-config flags in the Jenkins pipeline (Jenkinsfile.terraform)
# so this block intentionally has no hardcoded values.
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend values are injected at 'terraform init' time via -backend-config flags.
  # See jenkins/Jenkinsfile.terraform — 'Terraform Init' stage.
  backend "s3" {}
}
