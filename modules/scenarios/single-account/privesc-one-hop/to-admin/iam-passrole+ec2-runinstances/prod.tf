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
  name     = "pl-prod-prec-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-prec-to-admin-starting-user"
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

# Policy for the starting user (can PassRole and launch EC2 instances)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-prec-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

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
}

# Admin role (target of privilege escalation)
# Initially only trusts ec2.amazonaws.com
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-prec-to-admin-target-role"

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
    Name        = "pl-prod-prec-to-admin-target-role"
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
  name     = "pl-prod-prec-to-admin-instance-profile"
  role     = aws_iam_role.admin_role.name

  tags = {
    Name        = "pl-prod-prec-to-admin-instance-profile"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-runinstances"
    Purpose     = "admin-instance-profile"
  }
}

# Security group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  provider    = aws.prod
  name        = "pl-prod-prec-to-admin-sg"
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
    Name        = "pl-prod-prec-to-admin-sg"
    Environment = var.environment
    Scenario    = "iam-passrole+ec2-runinstances"
    Purpose     = "ec2-security-group"
  }
}

# NOTE: The actual EC2 instance will be launched by the demo script using user-data
# The starting user will:
# 1. Use PassRole to assign the admin role to an EC2 instance
# 2. Launch the EC2 instance with user-data script
# 3. The user-data script will use the admin role's credentials to attach AdministratorAccess to the starting user
# 4. The starting user then has admin permissions directly
#
# Example user-data script:
# #!/bin/bash
# STARTING_USER_NAME="pl-prod-prec-to-admin-starting-user"
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
