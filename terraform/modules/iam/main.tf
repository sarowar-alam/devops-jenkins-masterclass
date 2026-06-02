# ============================================================
# Module: iam
# Creates the IAM role, policy attachment, and instance profile
# that allow the EC2 instance to be managed via SSM Session Manager
# without any SSH key or open port 22.
#
# How it works:
#   1. aws_iam_role        — EC2 service can assume this role
#   2. Policy attachment   — grants AmazonSSMManagedInstanceCore
#      (allows SSM agent to register and accept session connections)
#   3. aws_iam_instance_profile — wrapper required to attach a
#      role to an EC2 instance at launch
# ============================================================

resource "aws_iam_role" "ec2_ssm" {
  name        = "${var.name_prefix}-ec2-ssm-role"
  description = "Allows EC2 instances to register with SSM and be managed via Session Manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEC2ToAssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "${var.name_prefix}-ec2-ssm-role" }
}

# AWS-managed policy: grants all permissions needed for SSM Session Manager
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile — required wrapper to attach an IAM role to an EC2 instance
resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.name_prefix}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
  tags = { Name = "${var.name_prefix}-ec2-ssm-profile" }
}
