terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# AppRunner UpdateService privilege escalation scenario
#
# This scenario demonstrates how a user with apprunner:UpdateService can exploit
# an existing App Runner service that has an admin role attached by updating both
# the container image and StartCommand to execute privilege escalation commands.

# Resource naming convention: pl-prod-apprunner-002-to-admin-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-apprunner-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-apprunner-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "apprunner-updateservice"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with App Runner update permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-apprunner-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationUpdateService"
        Effect = "Allow"
        Action = [
          "apprunner:UpdateService"
        ]
        Resource = "arn:aws:apprunner:*:${var.account_id}:service/pl-apprunner-002-to-admin/*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "apprunner:DescribeService",
          "apprunner:ListServices"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role (target of privilege escalation)
# This role is attached to the App Runner service as its instance role
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-apprunner-002-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-apprunner-002-to-admin-target-role"
    Environment = var.environment
    Scenario    = "apprunner-updateservice"
    Purpose     = "admin-target"
  }
}

# Attach full admin policy to the target role
resource "aws_iam_role_policy" "target_role_admin_policy" {
  provider = aws.prod
  name     = "pl-prod-apprunner-002-to-admin-target-role-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# Pre-existing App Runner service with benign container
# This represents an existing production service that will be compromised
resource "aws_apprunner_service" "target_service" {
  provider     = aws.prod
  service_name = "pl-apprunner-002-to-admin"

  source_configuration {
    auto_deployments_enabled = false

    image_repository {
      image_identifier      = "public.ecr.aws/nginx/nginx:alpine"
      image_repository_type = "ECR_PUBLIC"
      image_configuration {
        port = "80"
      }
    }
  }

  instance_configuration {
    instance_role_arn = aws_iam_role.target_role.arn
    cpu               = "1024"
    memory            = "2048"
  }

  # Ignore changes since demo/cleanup scripts modify the service configuration
  lifecycle {
    ignore_changes = [source_configuration]
  }

  tags = {
    Name        = "pl-apprunner-002-to-admin"
    Environment = var.environment
    Scenario    = "apprunner-updateservice"
    Purpose     = "target-service"
  }
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/apprunner-002-to-admin"
  description = "CTF flag for the apprunner-002 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-apprunner-002-to-admin-flag"
    Environment = var.environment
    Scenario    = "apprunner-updateservice"
    Purpose     = "ctf-flag"
  }
}
