terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + codebuild:CreateProject + codebuild:StartBuildBatch privilege escalation scenario
#
# This scenario demonstrates how an attacker with codebuild:CreateProject, codebuild:StartBuildBatch,
# and iam:PassRole permissions can escalate privileges to administrator by creating a CodeBuild
# project with a privileged role and executing a buildspec that grants admin access to themselves.

# Resource naming convention: pl-prod-cbcpsbb-to-admin-{resource-type}
# Provider: aws.prod (single account scenario)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-cbcpsbb-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-cbcpsbb-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+codebuild-createproject+codebuild-startbuildbatch"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (PassRole + CodeBuild permissions)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-cbcpsbb-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:CreateProject",
          "codebuild:StartBuildBatch",
          "codebuild:BatchGetBuilds",
          "codebuild:BatchGetBuildBatches",
          "codebuild:ListProjects"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:ListRoles"]
        Resource = "*"
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

# Target role with admin permissions that will be passed to CodeBuild
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-cbcpsbb-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-cbcpsbb-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+codebuild-createproject+codebuild-startbuildbatch"
    Purpose     = "target-role-for-codebuild"
  }
}

# Policy allowing the target role to grant admin access to the starting user
resource "aws_iam_role_policy" "target_role_policy" {
  provider = aws.prod
  name     = "pl-prod-cbcpsbb-to-admin-target-role-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${var.account_id}:log-group:/aws/codebuild/*"
      }
    ]
  })
}
