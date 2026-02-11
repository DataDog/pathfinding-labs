# Multi-hop privilege escalation: STS AssumeRole -> ECS PassRole + CreateCluster + RegisterTaskDefinition + RunTask
#
# This scenario demonstrates a two-hop privilege escalation path:
# 1. Attacker assumes a role with ECS permissions (sts:AssumeRole)
# 2. Using the role's credentials, attacker creates an ECS cluster and runs a Fargate task
#    with an admin role to escalate privileges (iam:PassRole + ecs:* permissions)
#
# Attack Path: starting_user -> (sts:AssumeRole) -> starting_role ->
#              (iam:PassRole + ecs:CreateCluster + ecs:RegisterTaskDefinition + ecs:RunTask) ->
#              admin_role (via ECS task) -> admin access

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# Resource naming convention: pl-prod-sts001-ecs002-{resource-type}
# All resources use provider = aws.prod

# =============================================================================
# STARTING USER (First principal in the attack chain)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-sts001-ecs002-starting-user"

  tags = {
    Name        = "pl-prod-sts001-ecs002-starting-user"
    Environment = var.environment
    Scenario    = "sts-001-to-ecs-002-to-admin"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user - can only assume the starting role
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-sts001-ecs002-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions1"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.starting_role.arn
      },
      {
        Sid    = "helpfulAdditionalPermissions1"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# STARTING ROLE (Second principal - has ECS permissions)
# =============================================================================

# This role has the ECS permissions needed for the privilege escalation
# The starting user can assume this role to gain ECS capabilities
resource "aws_iam_role" "starting_role" {
  provider = aws.prod
  name     = "pl-prod-sts001-ecs002-starting-role"

  # Trust policy allows the starting user to assume this role
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
    Name        = "pl-prod-sts001-ecs002-starting-role"
    Environment = var.environment
    Scenario    = "sts-001-to-ecs-002-to-admin"
    Purpose     = "starting-role"
  }
}

# Policy granting the starting role ECS permissions and PassRole on admin role
resource "aws_iam_role_policy" "starting_role_policy" {
  provider = aws.prod
  name     = "pl-prod-sts001-ecs002-starting-role-policy"
  role     = aws_iam_role.starting_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions1"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.admin_role.arn
      },
      {
        Sid    = "requiredPermissions2"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster",
          "ecs:RegisterTaskDefinition",
          "ecs:RunTask"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions1"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions2"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions3"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "cleanupPermissions1"
        Effect = "Allow"
        Action = [
          "ecs:StopTask",
          "ecs:DeregisterTaskDefinition",
          "ecs:DeleteCluster",
          "iam:ListAttachedUserPolicies",
          "iam:DetachUserPolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# ADMIN ROLE (Third principal - the target with admin permissions)
# =============================================================================

# This is the privileged role that the ECS task will use
# The task can then attach the AdministratorAccess policy to the starting user
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-sts001-ecs002-admin-role"

  # Trust policy allows ECS tasks to assume this role
  # Note: The starting role CANNOT assume this directly - must go through ECS
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
    Name        = "pl-prod-sts001-ecs002-admin-role"
    Environment = var.environment
    Scenario    = "sts-001-to-ecs-002-to-admin"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the admin role
# This gives the ECS task full admin permissions
resource "aws_iam_role_policy_attachment" "admin_role_admin" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
