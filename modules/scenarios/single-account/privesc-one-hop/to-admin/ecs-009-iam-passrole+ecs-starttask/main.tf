terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-passrole+ecs-starttask privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and ecs:StartTask can
# escalate privileges by exploiting an EXISTING task definition on an EC2 container
# instance that is already registered to the cluster. Unlike ecs-007 (which also
# requires ecs:RegisterContainerInstance), the attacker here does NOT need to
# register a container instance — one already exists. The attack flow:
# 1. A task definition and container instance already exist in the cluster
# 2. The attacker uses ecs:StartTask with --overrides to override the container
#    command AND the taskRoleArn, passing the admin role
# 3. The overridden command attaches AdministratorAccess to the starting user
# 4. The starting user now has admin access

# Resource naming convention: pl-prod-ecs-009-to-admin-{resource-type}
# ecs-009 = Pathfinding.cloud ID for this scenario

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ecs-009-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ecs-009-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask"
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
  name     = "pl-prod-ecs-009-to-admin-required-permissions"
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
          "ecs:StartTask"
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

# Helpful additional permissions for demonstration and cleanup
resource "aws_iam_user_policy" "starting_user_helpful" {
  provider = aws.prod
  name     = "pl-prod-ecs-009-to-admin-helpful-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "helpfulAdditionalPermissions1"
        Effect = "Allow"
        Action = [
          "ecs:ListContainerInstances",
          "ecs:ListTaskDefinitions",
          "ecs:DescribeTasks",
          "ecs:ListClusters",
          "ecs:StopTask"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions2"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions3"
        Effect = "Allow"
        Action = [
          "iam:DetachUserPolicy",
          "iam:ListAttachedUserPolicies"
        ]
        Resource = aws_iam_user.starting_user.arn
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
  name     = "pl-prod-ecs-009-to-admin-target-role"

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
    Name        = "pl-prod-ecs-009-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask"
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

# ECS cluster for running tasks on EC2 instances
resource "aws_ecs_cluster" "cluster" {
  provider = aws.prod
  name     = "pl-prod-ecs-009-cluster"

  tags = {
    Name        = "pl-prod-ecs-009-cluster"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask"
    Purpose     = "ecs-cluster"
  }
}

# =============================================================================
# TASK EXECUTION ROLE (For pulling container images)
# =============================================================================

# Execution role used by ECS to pull images and write logs
resource "aws_iam_role" "execution_role" {
  provider = aws.prod
  name     = "pl-prod-ecs-009-to-admin-execution-role"

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
    Name        = "pl-prod-ecs-009-to-admin-execution-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask"
    Purpose     = "task-execution-role"
  }
}

# Attach the ECS task execution policy to the execution role
resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# PRE-EXISTING TASK DEFINITION (Exploited via StartTask --overrides)
# =============================================================================

# This task definition already exists in the cluster. The attacker does NOT
# create it - they exploit it by using ecs:StartTask with --overrides to:
# 1. Override the container command to run a malicious AWS CLI command
# 2. Override the taskRoleArn to use the admin target role
resource "aws_ecs_task_definition" "existing_task" {
  provider = aws.prod
  family   = "pl-prod-ecs-009-existing-task"

  # EC2 launch type required for ecs:StartTask
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"

  # Execution role for pulling images
  execution_role_arn = aws_iam_role.execution_role.arn

  # NOTE: No taskRoleArn is set here - the attacker will override this
  # with the admin target role via ecs:StartTask --overrides

  container_definitions = jsonencode([
    {
      name      = "pl-prod-ecs-009-benign-container"
      image     = "amazon/aws-cli"
      cpu       = 256
      memory    = 512
      essential = true
      command   = ["echo", "hello"]
    }
  ])

  tags = {
    Name        = "pl-prod-ecs-009-existing-task"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask"
    Purpose     = "pre-existing-task-definition"
  }
}

# =============================================================================
# EC2 CONTAINER INSTANCE INFRASTRUCTURE (Required for ecs:StartTask)
# =============================================================================

# Get the latest ECS-optimized AMI
data "aws_ami" "ecs_optimized" {
  provider    = aws.prod
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC for EC2 instance
data "aws_vpc" "default" {
  provider = aws.prod
  default  = true
}

# Get default subnets in the VPC
data "aws_subnets" "default" {
  provider = aws.prod
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for ECS container instance
resource "aws_security_group" "container_instance" {
  provider    = aws.prod
  name        = "pl-prod-ecs-009-to-admin-sg"
  description = "Security group for ECS container instance in StartTask override scenario"
  vpc_id      = data.aws_vpc.default.id

  # Allow outbound traffic (needed for ECS agent to communicate)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for ECS agent"
  }

  tags = {
    Name        = "pl-prod-ecs-009-to-admin-sg"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask"
    Purpose     = "Security group for ECS container instance"
  }
}

# IAM role for EC2 instance (allows ECS agent to function)
resource "aws_iam_role" "container_instance" {
  provider = aws.prod
  name     = "pl-prod-ecs-009-to-admin-instance-role"

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
    Name        = "pl-prod-ecs-009-to-admin-instance-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask"
    Purpose     = "IAM role for ECS container instance"
  }
}

# Attach the ECS policy to the instance role
resource "aws_iam_role_policy_attachment" "container_instance_ecs" {
  provider   = aws.prod
  role       = aws_iam_role.container_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Instance profile
resource "aws_iam_instance_profile" "container_instance" {
  provider = aws.prod
  name     = "pl-prod-ecs-009-to-admin-instance-profile"
  role     = aws_iam_role.container_instance.name

  tags = {
    Name        = "pl-prod-ecs-009-to-admin-instance-profile"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask"
  }
}

# EC2 instance that will register with the ECS cluster
resource "aws_instance" "container_instance" {
  provider               = aws.prod
  ami                    = data.aws_ami.ecs_optimized.id
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.container_instance.name
  vpc_security_group_ids = [aws_security_group.container_instance.id]
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]

  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.cluster.name} >> /etc/ecs/ecs.config
              EOF

  tags = {
    Name        = "pl-prod-ecs-009-to-admin-instance"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask"
    Purpose     = "ECS container instance for StartTask override privilege escalation"
  }
}

# Note: Container instance ARN is not available via Terraform data source.
# The EC2 instance must register with the ECS cluster first (happens via user_data).
# The demo script will retrieve the container instance ARN via AWS CLI.
