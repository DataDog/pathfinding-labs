terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + cloudformation:CreateStack privilege escalation scenario
#
# This scenario demonstrates how an attacker with iam:PassRole and cloudformation:CreateStack
# permissions can escalate privileges to administrator by passing an admin role to CloudFormation
# and having CloudFormation create a new role with admin permissions that trusts the attacker.

# Resource naming convention: pl-prod-cloudformation-001-to-admin-{resource-type}
# Provider: aws.prod (single account scenario)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-cloudformation-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "cloudformation-001-iam-passrole-cloudformation"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (PassRole + CloudFormation permissions)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-001-to-admin-starting-user-policy"
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
        Sid    = "RequiredForExploitationCloudFormation"
        Effect = "Allow"
        Action = [
          "cloudformation:CreateStack"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role that will be passed to CloudFormation
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-001-to-admin-cfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudformation.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-cloudformation-001-to-admin-cfn-role"
    Environment = var.environment
    Scenario    = "cloudformation-001-iam-passrole-cloudformation"
    Purpose     = "admin-role-for-cloudformation"
  }
}

# Attach AdministratorAccess to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
