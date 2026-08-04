terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-passrole+batch-createcomputeenvironment+batch-createjobqueue+batch-registerjobdefinition+batch-submitjob
# privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and broad Batch permissions
# can create an entire Batch pipeline from scratch — compute environment, job queue,
# job definition with an admin jobRoleArn — and submit a job to escalate to admin.
#
# Unlike batch-001 (where the compute environment and job queue already exist),
# here the attacker creates ALL Batch infrastructure. Terraform only provisions
# the pre-existing IAM roles and networking that the attacker exploits.

# Resource naming convention: pl-prod-batch-003-to-admin-{resource-type}
# batch-003 = pathfinding.cloud ID for this scenario

# =============================================================================
# NETWORKING (Security Group for Fargate tasks)
# =============================================================================

# Security group for Batch Fargate tasks (egress-only for pulling images and API calls)
resource "aws_security_group" "batch" {
  provider    = aws.prod
  name        = "pl-prod-batch-003-to-admin-batch-sg"
  description = "Security group for Batch Fargate tasks - egress only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for image pulls and API calls"
  }

  tags = {
    Name        = "pl-prod-batch-003-to-admin-batch-sg"
    Environment = var.environment
    Scenario    = "iam-passrole+batch-createcomputeenvironment+batch-createjobqueue+batch-registerjobdefinition+batch-submitjob"
    Purpose     = "batch-security-group"
  }
}

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-batch-003-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-batch-003-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+batch-createcomputeenvironment+batch-createjobqueue+batch-registerjobdefinition+batch-submitjob"
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
  name     = "pl-prod-batch-003-to-admin-required-permissions"
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
        Resource = [
          aws_iam_role.admin_role.arn,
          aws_iam_role.execution_role.arn
        ]
      },
      {
        Sid    = "RequiredForExploitationBatchActions"
        Effect = "Allow"
        Action = [
          "batch:CreateComputeEnvironment",
          "batch:CreateJobQueue",
          "batch:RegisterJobDefinition",
          "batch:SubmitJob"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "batch:DescribeComputeEnvironments",
          "batch:DescribeJobQueues",
          "batch:DescribeJobs",
          "batch:DescribeJobDefinitions",
          "iam:ListAttachedUserPolicies",
          "iam:ListRoles",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE (Privilege Escalation Target)
# =============================================================================

# Admin role that will be passed as jobRoleArn in the Batch job definition.
# This role trusts ecs-tasks.amazonaws.com because Batch runs containers as ECS tasks.
resource "aws_iam_role" "admin_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-batch-003-to-admin-admin-role"

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
    Name        = "pl-prod-batch-003-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+batch-createcomputeenvironment+batch-createjobqueue+batch-registerjobdefinition+batch-submitjob"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# EXECUTION ROLE (Required for Fargate to pull images and write logs)
# =============================================================================

# Execution role for Batch/ECS Fargate tasks - handles container image pulls and log writing
resource "aws_iam_role" "execution_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-batch-003-to-admin-execution-role"

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
    Name        = "pl-prod-batch-003-to-admin-execution-role"
    Environment = var.environment
    Scenario    = "iam-passrole+batch-createcomputeenvironment+batch-createjobqueue+batch-registerjobdefinition+batch-submitjob"
    Purpose     = "execution-role"
  }
}

# Attach the standard ECS task execution role policy
resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# CTF FLAG
# =============================================================================

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they
# reach administrator-equivalent permissions (AdministratorAccess grants
# ssm:GetParameter implicitly, so no extra IAM wiring is needed).
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/batch-003-to-admin"
  description = "CTF flag for the batch-003 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-batch-003-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+batch-createcomputeenvironment+batch-createjobqueue+batch-registerjobdefinition+batch-submitjob"
    Purpose     = "ctf-flag"
  }
}
