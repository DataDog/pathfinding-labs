terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-passrole+ecs-starttask+ecs-registercontainerinstance privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, ecs:StartTask, and
# ssm:SendCommand can escalate privileges when an EC2 instance exists that is NOT
# registered to the target ECS cluster. Unlike ecs-009 (where the container instance
# is already registered), the attacker must first use SSM to reconfigure the ECS agent
# on the EC2 instance to join the target cluster, triggering ecs:RegisterContainerInstance.
# The attack flow:
# 1. An EC2 instance (ECS-optimized) exists but is pointed at a non-existent cluster
# 2. The attacker uses ssm:SendCommand to reconfigure the ECS agent to join the real cluster
# 3. The ECS agent calls ecs:RegisterContainerInstance, registering the EC2 to the cluster
# 4. The attacker uses ecs:StartTask with --overrides to override the container command
#    AND the taskRoleArn, passing the admin role
# 5. The overridden command attaches AdministratorAccess to the starting user
# 6. The starting user now has admin access

# Resource naming convention: pl-prod-ecs-007-to-admin-{resource-type}
# ecs-007 = Pathfinding.cloud ID for this scenario

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ecs-007-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ecs-007-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
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
  name     = "pl-prod-ecs-007-to-admin-required-permissions"
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
        Sid    = "requiredPermissions3"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
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
  name     = "pl-prod-ecs-007-to-admin-helpful-permissions"
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
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions3"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions4"
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
  name     = "pl-prod-ecs-007-to-admin-target-role"

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
    Name        = "pl-prod-ecs-007-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
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
# ECS CLUSTER (Task Execution Environment - EMPTY, no auto-registered instances)
# =============================================================================

# ECS cluster for running tasks on EC2 instances
# This cluster starts EMPTY - the EC2 instance is NOT registered to it
# The attacker must use SSM to reconfigure the ECS agent to join this cluster
resource "aws_ecs_cluster" "cluster" {
  provider = aws.prod
  name     = "pl-prod-ecs-007-cluster"

  tags = {
    Name        = "pl-prod-ecs-007-cluster"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
    Purpose     = "ecs-cluster"
  }
}

# =============================================================================
# TASK EXECUTION ROLE (For pulling container images)
# =============================================================================

# Execution role used by ECS to pull images and write logs
resource "aws_iam_role" "execution_role" {
  provider = aws.prod
  name     = "pl-prod-ecs-007-to-admin-execution-role"

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
    Name        = "pl-prod-ecs-007-to-admin-execution-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
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
  family   = "pl-prod-ecs-007-existing-task"

  # EC2 launch type required for ecs:StartTask
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"

  # Execution role for pulling images
  execution_role_arn = aws_iam_role.execution_role.arn

  # NOTE: No taskRoleArn is set here - the attacker will override this
  # with the admin target role via ecs:StartTask --overrides

  container_definitions = jsonencode([
    {
      name      = "pl-prod-ecs-007-benign-container"
      image     = "amazon/aws-cli"
      cpu       = 256
      memory    = 512
      essential = true
      command   = ["echo", "hello"]
    }
  ])

  tags = {
    Name        = "pl-prod-ecs-007-existing-task"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
    Purpose     = "pre-existing-task-definition"
  }
}

# =============================================================================
# EC2 CONTAINER INSTANCE INFRASTRUCTURE (NOT registered to cluster)
# =============================================================================
# The EC2 instance uses an ECS-optimized AMI but is configured to point at a
# NON-EXISTENT cluster ("pl-prod-ecs-007-holding"). This means:
# - The ECS agent starts but CANNOT register (the holding cluster doesn't exist)
# - The SSM agent runs and can receive commands
# - The attacker must use ssm:SendCommand to reconfigure the ECS agent to join
#   the real cluster (pl-prod-ecs-007-cluster), triggering RegisterContainerInstance

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
  name        = "pl-prod-ecs-007-to-admin-sg"
  description = "Security group for ECS container instance in RegisterContainerInstance + StartTask override scenario"
  vpc_id      = data.aws_vpc.default.id

  # Allow outbound traffic (needed for ECS agent and SSM agent to communicate)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for ECS agent and SSM agent"
  }

  tags = {
    Name        = "pl-prod-ecs-007-to-admin-sg"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
    Purpose     = "Security group for ECS container instance"
  }
}

# IAM role for EC2 instance (allows ECS agent and SSM agent to function)
resource "aws_iam_role" "container_instance" {
  provider = aws.prod
  name     = "pl-prod-ecs-007-to-admin-instance-role"

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
    Name        = "pl-prod-ecs-007-to-admin-instance-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
    Purpose     = "IAM role for ECS container instance"
  }
}

# Attach the ECS policy to the instance role (includes ecs:RegisterContainerInstance)
resource "aws_iam_role_policy_attachment" "container_instance_ecs" {
  provider   = aws.prod
  role       = aws_iam_role.container_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Attach SSM policy to the instance role (allows SSM agent to receive commands)
resource "aws_iam_role_policy_attachment" "container_instance_ssm" {
  provider   = aws.prod
  role       = aws_iam_role.container_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile
resource "aws_iam_instance_profile" "container_instance" {
  provider = aws.prod
  name     = "pl-prod-ecs-007-to-admin-instance-profile"
  role     = aws_iam_role.container_instance.name

  tags = {
    Name        = "pl-prod-ecs-007-to-admin-instance-profile"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
  }
}

# EC2 instance with ECS agent pointed at a NON-EXISTENT cluster
# The ECS agent will start but fail to register because the holding cluster doesn't exist.
# The attacker uses ssm:SendCommand to reconfigure the agent to join the real cluster.
resource "aws_instance" "container_instance" {
  provider               = aws.prod
  ami                    = data.aws_ami.ecs_optimized.id
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.container_instance.name
  vpc_security_group_ids = [aws_security_group.container_instance.id]
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]

  # Intentionally set a non-existent cluster to prevent auto-registration
  # The demo script will use SSM to reconfigure the agent to join the real cluster
  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=pl-prod-ecs-007-holding >> /etc/ecs/ecs.config
              EOF

  tags = {
    Name        = "pl-prod-ecs-007-to-admin-instance"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
    Purpose     = "Unregistered ECS container instance for RegisterContainerInstance + StartTask override privilege escalation"
  }
}

# Note: Container instance ARN is not available via Terraform data source.
# The EC2 instance is NOT registered to any cluster at deploy time.
# The demo script will:
# 1. Use ssm:SendCommand to reconfigure the ECS agent to join the real cluster
# 2. Wait for ecs:RegisterContainerInstance to complete
# 3. Retrieve the container instance ARN via AWS CLI
# 4. Use ecs:StartTask with --overrides to escalate privileges
