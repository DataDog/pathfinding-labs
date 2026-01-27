terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# codebuild:StartBuild privilege escalation scenario
#
# This scenario demonstrates how a user with codebuild:StartBuild permission can exploit
# an existing CodeBuild project that has an admin role by using buildspec-override to
# execute malicious commands that grant admin access to themselves.

# Resource naming convention: pl-prod-codebuild-002-to-admin-{resource-type}
# Provider: aws.prod (single account scenario)

# ==============================================================================
# SCENARIO-SPECIFIC STARTING USER
# ==============================================================================

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-codebuild-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-codebuild-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "codebuild-startbuild"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (StartBuild + discovery permissions)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-codebuild-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BasicIdentityPermissions"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeBuildStartBuildForPrivesc"
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeBuildHelpfulForDemo"
        Effect = "Allow"
        Action = [
          "codebuild:ListProjects",
          "codebuild:BatchGetProjects",
          "codebuild:BatchGetBuilds"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# PROJECT ROLE WITH ADMIN PERMISSIONS (TARGET)
# ==============================================================================

# Admin role that the existing CodeBuild project uses
resource "aws_iam_role" "project_role" {
  provider = aws.prod
  name     = "pl-prod-codebuild-002-to-admin-project-role"

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
    Name        = "pl-prod-codebuild-002-to-admin-project-role"
    Environment = var.environment
    Scenario    = "codebuild-startbuild"
    Purpose     = "project-admin-role"
  }
}

# Attach AdministratorAccess to the project role
resource "aws_iam_role_policy_attachment" "project_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.project_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ==============================================================================
# EXISTING CODEBUILD PROJECT
# ==============================================================================

# The existing CodeBuild project with an admin role
# Note: This project has a simple buildspec that just echoes "Hello World"
# The attacker will override this with a malicious buildspec using StartBuild
resource "aws_codebuild_project" "existing_project" {
  provider     = aws.prod
  name         = "pl-prod-codebuild-002-to-admin-existing-project"
  description  = "Existing CodeBuild project with admin role (vulnerable to buildspec override)"
  service_role = aws_iam_role.project_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - echo "Hello World from the existing project"
    EOT
  }

  tags = {
    Name        = "pl-prod-codebuild-002-to-admin-existing-project"
    Environment = var.environment
    Scenario    = "codebuild-startbuild"
    Purpose     = "vulnerable-project"
  }
}
