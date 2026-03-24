terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-passrole+ecs-registertaskdefinition+ecs-runtask privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, ecs:RegisterTaskDefinition,
# and ecs:RunTask can escalate privileges by:
# 1. Creating an ECS task definition that uses an admin role
# 2. Launching the task which runs with admin permissions
# 3. The task attaches admin policy to the starting user
# 4. Starting user now has admin access

# Resource naming convention: pl-prod-ecs-004-to-admin-{resource-type}
# ecs-004 = pathfinding.cloud ID for this scenario

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ecs-004-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ecs-004-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-runtask"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Required permissions policy for exploitation
resource "aws_iam_user_policy" "starting_user_required" {
  provider = aws.prod
  name     = "pl-prod-ecs-004-to-admin-required-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "requiredECSPermissions"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:RunTask"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE (Privilege Escalation Target)
# =============================================================================

# Target admin role that will be passed to ECS tasks
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-ecs-004-to-admin-target-role"

  # Trust policy allowing ECS tasks to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-ecs-004-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-runtask"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# ECS CLUSTER (Task Execution Environment)
# =============================================================================

# ECS cluster for running Fargate tasks
resource "aws_ecs_cluster" "cluster" {
  provider = aws.prod
  name     = "pl-prod-ecs-004-cluster"

  tags = {
    Name        = "pl-prod-ecs-004-cluster"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-runtask"
    Purpose     = "ecs-cluster"
  }
}
