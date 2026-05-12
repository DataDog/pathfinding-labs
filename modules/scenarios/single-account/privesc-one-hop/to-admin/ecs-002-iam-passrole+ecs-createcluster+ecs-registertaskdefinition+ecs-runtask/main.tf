terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# ECS PassRole privilege escalation scenario
#
# This scenario demonstrates how a user with ecs:CreateCluster, iam:PassRole,
# ecs:RegisterTaskDefinition, and ecs:RunTask can escalate privileges by
# creating an ECS cluster and running a Fargate task with a privileged role
# that grants the starting user admin access.

# Resource naming convention: pl-prod-ecs-002-to-admin-{resource-type}
# Provider: aws.prod (single-account scenario)

# =============================================================================
# STARTING USER (with access keys)
# =============================================================================

resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-ecs-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ecs-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the starting user the permissions needed for the attack
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ecs-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationECS"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster",
          "ecs:RegisterTaskDefinition",
          "ecs:RunTask"
        ]
        Resource = "*"
      },
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ecs:DescribeTasks",
          "iam:ListAttachedUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ROLE (with admin permissions)
# =============================================================================

# This is the privileged role that the ECS task will use
# The task can then attach the AdministratorAccess policy to the starting user
resource "aws_iam_role" "target_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-ecs-002-to-admin-target-role"

  # Trust policy allows ECS tasks to assume this role
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
    Name        = "pl-prod-ecs-002-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask"
    Purpose     = "target-role"
  }
}

# Attach AdministratorAccess policy to the target role
# This gives the ECS task full admin permissions
resource "aws_iam_role_policy_attachment" "target_role_admin" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/ecs-002-to-admin"
  description = "CTF flag for the ecs-002 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-ecs-002-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask"
    Purpose     = "ctf-flag"
  }
}
