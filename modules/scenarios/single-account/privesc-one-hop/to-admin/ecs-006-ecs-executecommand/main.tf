# ecs-executecommand privilege escalation scenario
#
# This scenario demonstrates how a user with ecs:ExecuteCommand can shell into
# a running ECS task and extract credentials from the container metadata service.
# The task runs with an admin role, so the extracted credentials grant admin access.
#
# Attack path:
# 1. Attacker identifies a running ECS task with an admin role attached
# 2. Uses ecs:ExecuteCommand to open a shell session in the container
# 3. Curls the container metadata service to extract IAM credentials
# 4. Uses the extracted admin credentials for full account access

# Resource naming convention: pl-prod-ecs-006-to-admin-{resource-type}
# ecs-006 = Pathfinding.cloud ID for ECS ExecuteCommand privilege escalation

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ecs-006-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ecs-006-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "ecs-executecommand"
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
  name     = "pl-prod-ecs-006-to-admin-required-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "executeCommandOnClusterAndTasks"
        Effect = "Allow"
        Action = [
          "ecs:ExecuteCommand"
        ]
        Resource = [
          "arn:aws:ecs:*:${var.account_id}:cluster/${aws_ecs_cluster.cluster.name}",
          "arn:aws:ecs:*:${var.account_id}:task/${aws_ecs_cluster.cluster.name}/*"
        ]
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

# Helpful additional permissions for demonstration
resource "aws_iam_user_policy" "starting_user_helpful" {
  provider = aws.prod
  name     = "pl-prod-ecs-006-to-admin-helpful-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "helpfulAdditionalPermissions"
        Effect = "Allow"
        Action = [
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition",
          "ecs:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE (Task Role - Privilege Escalation Target)
# =============================================================================

# Target admin role that the ECS task runs with
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-ecs-006-to-admin-target-role"

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
    Name        = "pl-prod-ecs-006-to-admin-target-role"
    Environment = var.environment
    Scenario    = "ecs-executecommand"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# SSM permissions required for ECS Exec to work
# The task role needs these permissions to establish the SSM session
resource "aws_iam_role_policy" "target_role_ssm" {
  provider = aws.prod
  name     = "pl-prod-ecs-006-to-admin-ssm-permissions"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ssmMessagesPermissions"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# EXECUTION ROLE (For ECS Task Execution)
# =============================================================================

# Execution role for pulling images and logging
resource "aws_iam_role" "execution_role" {
  provider = aws.prod
  name     = "pl-prod-ecs-006-to-admin-execution-role"

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
    Name        = "pl-prod-ecs-006-to-admin-execution-role"
    Environment = var.environment
    Scenario    = "ecs-executecommand"
    Purpose     = "ecs-execution-role"
  }
}

# Attach the standard ECS task execution role policy
resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Get current region for log configuration
data "aws_region" "current" {
  provider = aws.prod
}

# =============================================================================
# NETWORKING (VPC and Security Group)
# =============================================================================

# Get default VPC for Fargate tasks
data "aws_vpc" "default" {
  provider = aws.prod
  default  = true
}

# Get subnets in the VPC
data "aws_subnets" "default" {
  provider = aws.prod
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  provider    = aws.prod
  name        = "pl-prod-ecs-006-to-admin-sg"
  description = "Security group for ECS ExecuteCommand scenario tasks"
  vpc_id      = data.aws_vpc.default.id

  # Allow all outbound traffic (needed for metadata service and image pulls)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # No ingress needed - the task only needs outbound connectivity

  tags = {
    Name        = "pl-prod-ecs-006-to-admin-sg"
    Environment = var.environment
    Scenario    = "ecs-executecommand"
    Purpose     = "Security group for ECS tasks"
  }
}

# =============================================================================
# ECS CLUSTER AND SERVICE
# =============================================================================

# ECS cluster for running the Fargate service
resource "aws_ecs_cluster" "cluster" {
  provider = aws.prod
  name     = "pl-prod-ecs-006-to-admin-cluster"

  # Enable Container Insights for better observability
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "pl-prod-ecs-006-to-admin-cluster"
    Environment = var.environment
    Scenario    = "ecs-executecommand"
    Purpose     = "ecs-cluster"
  }
}

# CloudWatch log group for container logs
resource "aws_cloudwatch_log_group" "ecs" {
  provider          = aws.prod
  name              = "/ecs/pl-prod-ecs-006-to-admin"
  retention_in_days = 7

  tags = {
    Name        = "pl-prod-ecs-006-to-admin-logs"
    Environment = var.environment
    Scenario    = "ecs-executecommand"
    Purpose     = "Container logs"
  }
}

# Task definition with admin role attached
resource "aws_ecs_task_definition" "task" {
  provider                 = aws.prod
  family                   = "pl-prod-ecs-006-to-admin-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.target_role.arn

  container_definitions = jsonencode([
    {
      name      = "sleep-container"
      image     = "public.ecr.aws/docker/library/alpine:latest"
      essential = true
      command   = ["sleep", "infinity"]

      # Enable pseudo-terminal for interactive shell access
      linuxParameters = {
        initProcessEnabled = true
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name        = "pl-prod-ecs-006-to-admin-task"
    Environment = var.environment
    Scenario    = "ecs-executecommand"
    Purpose     = "Task definition with admin role"
  }
}

# ECS Service that keeps the task running with ECS Exec enabled
# This is the key vulnerability - ECS Exec allows shell access to the container
resource "aws_ecs_service" "service" {
  provider        = aws.prod
  name            = "pl-prod-ecs-006-to-admin-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # CRITICAL: This enables the ECS Exec vulnerability
  # Anyone with ecs:ExecuteCommand permission can shell into this task
  enable_execute_command = true

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  # Ensure task definition is created first
  depends_on = [
    aws_iam_role_policy_attachment.execution_role_policy,
    aws_iam_role_policy_attachment.target_role_admin,
    aws_iam_role_policy.target_role_ssm
  ]

  tags = {
    Name        = "pl-prod-ecs-006-to-admin-service"
    Environment = var.environment
    Scenario    = "ecs-executecommand"
    Purpose     = "Vulnerable ECS service with exec enabled"
  }
}
