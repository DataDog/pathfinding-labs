terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  provider    = aws.prod
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ec2-004-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ec2-004-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-requestspotinstances"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (can PassRole and request spot instances)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ec2-004-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.admin_role.arn
      },
      {
        Sid    = "RequiredForExploitationRequestSpotInstances"
        Effect = "Allow"
        Action = [
          "ec2:RequestSpotInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeImages",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:CreateTags",
          "iam:GetRole",
          "iam:ListInstanceProfiles",
          "iam:ListRoles"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role (target of privilege escalation)
# Initially only trusts ec2.amazonaws.com
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-ec2-004-to-admin-target-role"

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
    Name        = "pl-prod-ec2-004-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-requestspotinstances"
    Purpose     = "admin-target"
  }
}

# Attach administrator access to the admin role
resource "aws_iam_role_policy_attachment" "admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Instance profile for the admin role
resource "aws_iam_instance_profile" "admin_instance_profile" {
  provider = aws.prod
  name     = "pl-prod-ec2-004-to-admin-instance-profile"
  role     = aws_iam_role.admin_role.name

  tags = {
    Name        = "pl-prod-ec2-004-to-admin-instance-profile"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-requestspotinstances"
    Purpose     = "admin-instance-profile"
  }
}

# Security group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  provider    = aws.prod
  name        = "pl-prod-ec2-004-to-admin-sg"
  description = "Security group for PassRole+RequestSpotInstances privilege escalation scenario"
  vpc_id      = var.vpc_id

  # Allow outbound HTTPS for AWS API calls
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS outbound for AWS API calls"
  }

  # Allow all outbound traffic (EC2 instances need to communicate with AWS services)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "pl-prod-ec2-004-to-admin-sg"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-requestspotinstances"
    Purpose     = "ec2-security-group"
  }
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/ec2-004-to-admin"
  description = "CTF flag for the ec2-004 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-ec2-004-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-requestspotinstances"
    Purpose     = "ctf-flag"
  }
}

# NOTE: The actual EC2 spot instance will be launched by the demo script using user-data
# The starting user will:
# 1. Use PassRole to assign the admin role to a spot instance request
# 2. Request a spot instance with user-data script
# 3. The user-data script will use the admin role's credentials to attach AdministratorAccess to the starting user
# 4. The starting user then has admin permissions directly
#
# Example user-data script:
# #!/bin/bash
# STARTING_USER_NAME="pl-prod-ec2-004-to-admin-starting-user"
#
# # Wait for IAM role to be available
# sleep 10
#
# # Attach AdministratorAccess policy to the starting user
# aws iam attach-user-policy \
#   --user-name $STARTING_USER_NAME \
#   --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
#
# echo "AdministratorAccess attached to $STARTING_USER_NAME"
