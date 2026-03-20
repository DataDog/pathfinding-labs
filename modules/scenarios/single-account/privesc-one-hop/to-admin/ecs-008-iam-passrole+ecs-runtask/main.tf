terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-passrole+ecs-runtask privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and ecs:RunTask can
# escalate privileges by exploiting an EXISTING task definition via Fargate:
# 1. A task definition already exists in the cluster (deployed by Terraform)
# 2. The attacker uses ecs:RunTask with --overrides to override the container
#    command AND the taskRoleArn, passing the admin role
# 3. The overridden command attaches AdministratorAccess to the starting user
# 4. Starting user now has admin access
#
# Key difference from ecs-004: No ecs:RegisterTaskDefinition needed.
# The attacker overrides an existing task definition at run time.

# Resource naming convention: pl-prod-ecs-008-to-admin-{resource-type}
# ecs-008 = pathfinding.cloud ID for this scenario

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ecs-008-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ecs-008-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-runtask"
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
  name     = "pl-prod-ecs-008-to-admin-required-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions1"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.target_role.arn,
          aws_iam_role.execution_role.arn
        ]
      },
      {
        Sid    = "requiredPermissions2"
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        Resource = "*"
      },
      {
        Sid    = "identityPermission"
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
# TARGET ADMIN ROLE (Privilege Escalation Target)
# =============================================================================

# Target admin role that will be passed to ECS tasks via --overrides
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-ecs-008-to-admin-target-role"

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
    Name        = "pl-prod-ecs-008-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-runtask"
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
# ECS TASK EXECUTION ROLE (Required for Fargate to pull images)
# =============================================================================

# Execution role allows ECS Fargate to pull container images and write logs
resource "aws_iam_role" "execution_role" {
  provider = aws.prod
  name     = "pl-prod-ecs-008-to-admin-execution-role"

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
    Name        = "pl-prod-ecs-008-to-admin-execution-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-runtask"
    Purpose     = "task-execution-role"
  }
}

# Attach the standard ECS task execution policy
resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# ECS CLUSTER (Task Execution Environment)
# =============================================================================

# ECS cluster for running Fargate tasks
resource "aws_ecs_cluster" "cluster" {
  provider = aws.prod
  name     = "pl-prod-ecs-008-cluster"

  tags = {
    Name        = "pl-prod-ecs-008-cluster"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-runtask"
    Purpose     = "ecs-cluster"
  }
}

# =============================================================================
# PRE-EXISTING TASK DEFINITION (The attacker will override this at runtime)
# =============================================================================

# This task definition already exists in the cluster. The attacker does NOT
# create their own task definition. Instead, they use ecs:RunTask with
# --overrides to change the container command and taskRoleArn at runtime.
#
# Note: No taskRoleArn is set here. The attacker will override it with the
# admin target role using the --overrides parameter.
resource "aws_ecs_task_definition" "existing_task" {
  provider = aws.prod
  family   = "pl-prod-ecs-008-existing-task"

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "amazon/aws-cli"
      essential = true
      command   = ["echo", "hello"]
    }
  ])

  tags = {
    Name        = "pl-prod-ecs-008-existing-task"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-runtask"
    Purpose     = "existing-task-definition"
  }
}
