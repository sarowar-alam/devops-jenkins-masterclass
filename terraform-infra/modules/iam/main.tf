resource "aws_iam_role" "jenkins_ec2" {
  name = "${var.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-ec2-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow the Jenkins EC2 instance role to send emails via SES
# (no SMTP credentials needed — uses instance metadata for auth)
resource "aws_iam_role_policy" "ses_send" {
  name = "${var.name_prefix}-ses-send-policy"
  role = aws_iam_role.jenkins_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_ec2" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.jenkins_ec2.name

  tags = {
    Name = "${var.name_prefix}-ec2-profile"
  }
}
