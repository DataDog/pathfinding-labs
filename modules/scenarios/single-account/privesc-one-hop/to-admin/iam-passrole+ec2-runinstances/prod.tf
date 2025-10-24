terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Get default VPC
data "aws_vpc" "default" {
  provider = aws.prod
  default  = true
}

# Get default subnet
data "aws_subnets" "default" {
  provider = aws.prod
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
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
  name     = "pl-prod-one-hop-prec-starting-user"

  tags = {
    Name        = "pl-prod-one-hop-prec-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-runinstances"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Minimal policy for the starting user (can assume both roles)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-one-hop-prec-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          "arn:aws:iam::${var.account_id}:role/pl-prod-one-hop-prec-role",
          "arn:aws:iam::${var.account_id}:role/pl-prod-one-hop-prec-admin-role"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role (target of privilege escalation)
# Initially only trusts ec2.amazonaws.com, will be backdoored by EC2 instance
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-prec-admin-role"

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
    Name        = "pl-prod-one-hop-prec-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-runinstances"
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
  name     = "pl-prod-one-hop-prec-instance-profile"
  role     = aws_iam_role.admin_role.name

  tags = {
    Name        = "pl-prod-one-hop-prec-instance-profile"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-runinstances"
    Purpose     = "admin-instance-profile"
  }
}

# Role that can PassRole and launch EC2 instances (privilege escalation vector)
resource "aws_iam_role" "privesc_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-prec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.starting_user.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-one-hop-prec-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-runinstances"
    Purpose     = "vulnerable-role"
  }
}

# Policy that allows PassRole and EC2 operations
resource "aws_iam_policy" "privesc_policy" {
  provider    = aws.prod
  name        = "pl-prod-one-hop-passrole-ec2-policy"
  description = "Allows PassRole on admin role and launching EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.admin_role.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeImages",
           "ec2:DescribeVpcs",
           "ec2:DescribeSubnets",
           "ec2:CreateTags",
           "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-one-hop-passrole-ec2-policy"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-runinstances"
  }
}

# Attach the policy to the privilege escalation role
resource "aws_iam_role_policy_attachment" "privesc_policy_attachment" {
  provider   = aws.prod
  role       = aws_iam_role.privesc_role.name
  policy_arn = aws_iam_policy.privesc_policy.arn
}

# Security group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  provider    = aws.prod
  name        = "pl-prod-one-hop-prec-security-group"
  description = "Security group for PassRole+EC2 privilege escalation scenario"
  vpc_id      = data.aws_vpc.default.id

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
    Name        = "pl-prod-one-hop-prec-security-group"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-runinstances"
    Purpose     = "ec2-security-group"
  }
}

# NOTE: The actual EC2 instance will be launched by the demo script using user-data
# The user-data script will:
# 1. Use the admin role's credentials (from instance metadata)
# 2. Update the admin role's trust policy to add the starting user
# 3. Allow the starting user to directly assume the admin role
#
# Example user-data script:
# #!/bin/bash
# STARTING_USER_ARN="arn:aws:iam::${var.account_id}:user/pl-prod-one-hop-prec-starting-user"
# ADMIN_ROLE_NAME="pl-prod-one-hop-prec-admin-role"
#
# # Get current trust policy
# aws iam get-role --role-name $ADMIN_ROLE_NAME --query 'Role.AssumeRolePolicyDocument' --output json > /tmp/policy.json
#
# # Add starting user to trust policy
# jq --arg arn "$STARTING_USER_ARN" '.Statement += [{"Effect": "Allow", "Principal": {"AWS": $arn}, "Action": "sts:AssumeRole"}]' /tmp/policy.json > /tmp/new-policy.json
#
# # Update the role's trust policy
# aws iam update-assume-role-policy --role-name $ADMIN_ROLE_NAME --policy-document file:///tmp/new-policy.json
