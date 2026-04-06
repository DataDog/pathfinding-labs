terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-passrole+ecs-registertaskdefinition+ecs-starttask privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, ecs:RegisterTaskDefinition,
# and ecs:StartTask can escalate privileges by:
# 1. Creating an ECS task definition that uses an admin role
# 2. Starting the task which runs with admin permissions
# 3. The task attaches admin policy to the starting user
# 4. Starting user now has admin access

# Resource naming convention: pl-prod-ecs-005-to-admin-{resource-type}
# ecs-005 = Pathfinding.cloud ID for this scenario

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ecs-005-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ecs-005-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-starttask"
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
  name     = "pl-prod-ecs-005-to-admin-required-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "RequiredForExploitationECS"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:StartTask"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "ecs:ListContainerInstances",
          "ecs:DescribeTasks",
          "ecs:DeregisterTaskDefinition",
          "ecs:StopTask",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "iam:DetachUserPolicy",
          "iam:ListAttachedUserPolicies"
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
  name     = "pl-prod-ecs-005-to-admin-target-role"

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
    Name        = "pl-prod-ecs-005-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-starttask"
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
  name     = "pl-prod-ecs-005-cluster"

  tags = {
    Name        = "pl-prod-ecs-005-cluster"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-starttask"
    Purpose     = "ecs-cluster"
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
# Get default subnet in the VPC
# Security group for ECS container instance
resource "aws_security_group" "container_instance" {
  provider    = aws.prod
  name        = "pl-prod-ecs-005-to-admin-sg"
  description = "Security group for ECS container instance in StartTask scenario"
  vpc_id      = var.vpc_id

  # Allow outbound traffic (needed for ECS agent to communicate)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for ECS agent"
  }

  tags = {
    Name        = "pl-prod-ecs-005-to-admin-sg"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-starttask"
    Purpose     = "Security group for ECS container instance"
  }
}

# IAM role for EC2 instance (allows ECS agent to function)
resource "aws_iam_role" "container_instance" {
  provider = aws.prod
  name     = "pl-prod-ecs-005-to-admin-instance-role"

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
    Name        = "pl-prod-ecs-005-to-admin-instance-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-starttask"
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
  name     = "pl-prod-ecs-005-to-admin-instance-profile"
  role     = aws_iam_role.container_instance.name

  tags = {
    Name        = "pl-prod-ecs-005-to-admin-instance-profile"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-starttask"
  }
}

# EC2 instance that will register with the ECS cluster
resource "aws_instance" "container_instance" {
  provider               = aws.prod
  ami                    = data.aws_ami.ecs_optimized.id
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.container_instance.name
  vpc_security_group_ids = [aws_security_group.container_instance.id]
  subnet_id              = var.subnet_id

  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.cluster.name} >> /etc/ecs/ecs.config
              EOF

  tags = {
    Name        = "pl-prod-ecs-005-to-admin-instance"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-registertaskdefinition+ecs-starttask"
    Purpose     = "ECS container instance for StartTask privilege escalation"
  }
}

# Note: Container instance ARN is not available via Terraform data source
# The EC2 instance must register with the ECS cluster first (happens via user_data)
# The demo script will retrieve the container instance ARN via AWS CLI
