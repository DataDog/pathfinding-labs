# SSM pivot role — assumed cross-account by the dev pathfinding starting user.
# After assumption, this role uses ssm:SendCommand / ssm:StartSession to reach the
# EC2 instance with the admin instance profile and retrieve credentials via IMDS.
resource "aws_iam_role" "ssm_pivot_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-ssm-ec2-pivot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDevStartingUserToAssume"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.dev_account_id}:user/pl-dev-ssm-ec2-starting-user"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-ssm-ec2-pivot-role"
    Environment = "prod"
    Scenario    = "ssm-startsession-ec2-admin"
    Purpose     = "pivot-role"
  }
}

# Inline policy on the pivot role granting SSM exploitation permissions
# and helpful recon permissions.
resource "aws_iam_role_policy" "ssm_pivot_role_policy" {
  provider = aws.prod
  name     = "pl-prod-ssm-ec2-pivot-policy"
  role     = aws_iam_role.ssm_pivot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationSSM"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
        ]
        Resource = [
          "arn:aws:ec2:*:${var.prod_account_id}:instance/*",
          "arn:aws:ssm:*::document/AWS-RunShellScript",
          "*",
        ]
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ssm:DescribeInstanceInformation",
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role assigned to the EC2 instance via its instance profile.
# The attacker retrieves temporary credentials for this role through IMDS
# after gaining shell access to the instance.
resource "aws_iam_role" "ec2_admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-ssm-ec2-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2ToAssume"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-ssm-ec2-admin-role"
    Environment = "prod"
    Scenario    = "ssm-startsession-ec2-admin"
    Purpose     = "admin-target"
  }
}

# Inline admin policy on the EC2 role — grants full AWS access, which is what
# the attacker obtains after calling IMDS for the instance credentials.
resource "aws_iam_role_policy" "ec2_admin_role_policy" {
  provider = aws.prod
  name     = "pl-prod-ssm-ec2-admin-policy"
  role     = aws_iam_role.ec2_admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AdminAccess"
        Effect   = "Allow"
        Action   = ["*"]
        Resource = ["*"]
      }
    ]
  })
}

# Instance profile that attaches the admin role to the EC2 instance.
resource "aws_iam_instance_profile" "ec2_profile" {
  provider = aws.prod
  name     = "pl-prod-ssm-ec2-instance-profile"
  role     = aws_iam_role.ec2_admin_role.name
}

# Amazon Linux 2023 — SSM agent is pre-installed and starts automatically,
# so no user_data bootstrapping is required.
data "aws_ami" "amazon_linux_2023" {
  provider    = aws.prod
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Use the default VPC subnets in the prod account. The instance does not need
# a public IP because SSM communicates over the AWS managed endpoint — no SSH
# or inbound security-group rules are required.
data "aws_vpc" "default" {
  provider = aws.prod
  default  = true
}

data "aws_subnets" "default" {
  provider = aws.prod

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# EC2 target instance. IMDSv1 is intentionally left enabled (http_tokens =
# "optional") so the attacker can retrieve the instance role credentials with a
# plain curl to 169.254.169.254 — no token request required, matching the
# typical real-world misconfiguration this scenario demonstrates.
resource "aws_instance" "target_ec2" {
  provider             = aws.prod
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t3.micro"
  subnet_id            = data.aws_subnets.default.ids[0]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "optional"
  }

  tags = {
    Name        = "pl-prod-ssm-ec2-instance"
    Environment = "prod"
    Scenario    = "ssm-startsession-ec2-admin"
    Purpose     = "target-instance"
  }
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after
# escalating to the EC2 admin role (which has full AWS access, including
# ssm:GetParameter). No extra IAM wiring is needed.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin"
  description = "CTF flag for the ssm-startsession-ec2-admin-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-ssm-ec2-flag"
    Environment = "prod"
    Scenario    = "ssm-startsession-ec2-admin"
    Purpose     = "ctf-flag"
  }
}
