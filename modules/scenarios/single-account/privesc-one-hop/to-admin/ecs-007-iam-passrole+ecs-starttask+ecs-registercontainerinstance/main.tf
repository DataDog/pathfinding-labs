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
# Based on: https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path
#
# This scenario demonstrates how an attacker with RCE on an EC2 instance can
# escalate to admin if the instance role has ecs:RegisterContainerInstance,
# ecs:StartTask, iam:PassRole, and ecs:DeregisterContainerInstance.
#
# The starting principal is the EC2 instance role. The attacker (with RCE):
# 1. Retrieves instance identity document + signature from IMDS
# 2. Calls ecs:RegisterContainerInstance directly via the API to register
#    the EC2 to the target ECS cluster
# 3. Reconfigures the ECS agent to join the cluster (so it can execute tasks)
# 4. Calls ecs:StartTask with --overrides to override the taskRoleArn (passing
#    the admin role) and the container command
# 5. The overridden command attaches AdministratorAccess to the instance role
# 6. The EC2 instance now has admin access
#
# The demo uses SSM SendCommand to simulate RCE (initial access to the EC2).
# SSM is NOT part of the attack permissions - it's a lab simulation mechanism.

# Resource naming convention: pl-prod-ecs-007-to-admin-{resource-type}
# ecs-007 = Pathfinding.cloud ID for this scenario

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
# The attacker must call ecs:RegisterContainerInstance directly to register
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
# EC2 CONTAINER INSTANCE INFRASTRUCTURE (STARTING PRINCIPAL)
# =============================================================================
# The EC2 instance role is the STARTING PRINCIPAL for this scenario.
# It represents a compromised EC2 instance where the attacker has RCE.
#
# The instance uses an ECS-optimized AMI but is configured to point at a
# NON-EXISTENT cluster ("pl-prod-ecs-007-holding"). This means:
# - The ECS agent starts but CANNOT register (the holding cluster doesn't exist)
# - The attacker calls ecs:RegisterContainerInstance directly via the API
# - The attacker then reconfigures the ECS agent to join the real cluster
#
# The instance role has ONLY the 4 permissions from the original research:
# - ecs:RegisterContainerInstance
# - ecs:StartTask
# - ecs:DeregisterContainerInstance
# - iam:PassRole (scoped to target + execution roles)
#
# SSM is attached separately for demo simulation of RCE (not an attack permission).

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
# Get default subnets in the VPC
# Security group for ECS container instance
resource "aws_security_group" "container_instance" {
  provider    = aws.prod
  name        = "pl-prod-ecs-007-to-admin-sg"
  description = "Security group for ECS container instance in RegisterContainerInstance + StartTask override scenario"
  vpc_id      = var.vpc_id

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

# IAM role for EC2 instance - THIS IS THE STARTING PRINCIPAL
# Has the 4 attack permissions from the original research
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
    Purpose     = "starting-principal"
  }
}

# Attack permissions - the 4 permissions from the original research
# Ref: https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path
resource "aws_iam_role_policy" "container_instance_attack_permissions" {
  provider = aws.prod
  name     = "pl-prod-ecs-007-to-admin-attack-permissions"
  role     = aws_iam_role.container_instance.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationECS"
        Effect = "Allow"
        Action = [
          "ecs:RegisterContainerInstance",
          "ecs:DeregisterContainerInstance",
          "ecs:StartTask"
        ]
        Resource = "*"
      },
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.target_role.arn,
          aws_iam_role.execution_role.arn
        ]
      }
    ]
  })
}

# ECS agent operational permissions - NOT attack permissions
# These are standard permissions that the ECS agent needs to communicate with the
# ECS control plane (discover endpoint, poll for tasks, report status). Any EC2
# instance running the ECS agent would normally have these via the managed policy
# AmazonEC2ContainerServiceforEC2Role. They are separated from the attack permissions
# to clearly distinguish between:
# - Attack permissions (the 4 from the research that enable the escalation)
# - Agent permissions (standard ECS infrastructure that was already present)
resource "aws_iam_role_policy" "container_instance_agent_permissions" {
  provider = aws.prod
  name     = "pl-prod-ecs-007-to-admin-agent-permissions"
  role     = aws_iam_role.container_instance.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HelpfulForExploitationAgentOperational"
        Effect = "Allow"
        Action = [
          "ecs:DiscoverPollEndpoint",
          "ecs:Poll",
          "ecs:StartTelemetrySession",
          "ecs:SubmitTaskStateChange",
          "ecs:SubmitContainerStateChange",
          "ecs:SubmitAttachment"
        ]
        Resource = "*"
      },
      {
        # Helpful for observing attack progress: verify registration, discover task definitions, monitor task status
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "ecs:ListContainerInstances",
          "ecs:ListTaskDefinitions",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
      }
    ]
  })
}

# SSM policy - NOT an attack permission, only used for demo simulation of RCE
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
# The attacker calls ecs:RegisterContainerInstance directly via the API.
resource "aws_instance" "container_instance" {
  provider               = aws.prod
  ami                    = data.aws_ami.ecs_optimized.id
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.container_instance.name
  vpc_security_group_ids = [aws_security_group.container_instance.id]
  subnet_id              = var.subnet_id

  # Intentionally set a non-existent cluster to prevent auto-registration
  # The attacker will call RegisterContainerInstance directly for the real cluster
  # Install AWS CLI - the ECS-optimized AMI doesn't include it by default
  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=pl-prod-ecs-007-holding >> /etc/ecs/ecs.config
              yum install -y awscli
              EOF

  tags = {
    Name        = "pl-prod-ecs-007-to-admin-instance"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
    Purpose     = "Compromised EC2 for RegisterContainerInstance + StartTask override privilege escalation"
  }
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/ecs-007-to-admin"
  description = "CTF flag for the ecs-007 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-ecs-007-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-starttask+ecs-registercontainerinstance"
    Purpose     = "ctf-flag"
  }
}
