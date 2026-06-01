terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# batch-submitjob privilege escalation scenario (batch-002)
#
# This scenario demonstrates how a principal with only batch:SubmitJob can escalate
# privileges by overriding the command of a pre-existing Batch job definition that
# already carries a privileged jobRoleArn. No iam:PassRole or batch:RegisterJobDefinition
# is required — the attacker reuses the admin jobRoleArn embedded in the existing job
# definition by submitting a new job with ContainerOverrides.Command to run their payload.
#
# Attack path:
#   starting_user (batch:SubmitJob) -> ContainerOverrides.Command on existing admin-role JD
#   -> Batch container runs as admin jobRoleArn -> attaches AdministratorAccess to starting_user
#   -> admin access -> ssm:GetParameter -> CTF flag

# Resource naming convention: pl-prod-batch-002-to-admin-{purpose}

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user.
# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band so
# destroy still succeeds if the scenario is disabled without running cleanup_attack.sh first.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-batch-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-batch-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "batch-submitjob"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# The starting user's policy grants only batch:SubmitJob (the required permission)
# plus helpful recon permissions to make manual exploitation navigable.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-batch-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationSubmitJob"
        Effect = "Allow"
        Action = [
          "batch:SubmitJob"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "batch:DescribeJobDefinitions",
          "batch:DescribeJobQueues",
          "batch:DescribeJobs",
          "batch:DescribeComputeEnvironments"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# ADMIN ROLE (Pre-existing privileged jobRoleArn — attack target)
# =============================================================================

# This role represents a pre-existing privileged job role that a developer
# attached to a Batch job definition for a legitimate maintenance workflow.
# The attacker exploits it by overriding the container command at submit time
# without needing to register a new job definition or pass the role themselves.
#
# force_detach_policies = true ensures destroy succeeds even if the demo
# script attached additional managed policies out-of-band.
resource "aws_iam_role" "admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-batch-002-to-admin-admin-role"

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
    Name        = "pl-prod-batch-002-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "batch-submitjob"
    Purpose     = "admin-target"
  }
}

resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# EXECUTION ROLE (Required for Fargate to pull images and write logs)
# =============================================================================

# Fargate needs a separate executionRoleArn to pull the container image from ECR
# and push logs to CloudWatch. This is infrastructure boilerplate — it is NOT
# exploitable on its own (no admin permissions).
resource "aws_iam_role" "exec_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-batch-002-to-admin-exec-role"

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
    Name        = "pl-prod-batch-002-to-admin-exec-role"
    Environment = var.environment
    Scenario    = "batch-submitjob"
    Purpose     = "execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "exec_role_ecs_policy" {
  provider   = aws.prod
  role       = aws_iam_role.exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# NOTE: AWS Batch service-linked role
# =============================================================================
# The Batch SLR (batch.amazonaws.com) is NOT created here. batch-001 already
# creates it and it is account-wide — creating it a second time would fail with
# a conflict. The compute environment below depends on it existing; if batch-001
# is not enabled, apply batch-001 first or create the SLR manually.

# =============================================================================
# CLOUDWATCH LOGS
# =============================================================================

resource "aws_cloudwatch_log_group" "batch_logs" {
  provider          = aws.prod
  name              = "/pl/batch/batch-002-to-admin"
  retention_in_days = 7

  tags = {
    Name        = "pl-prod-batch-002-to-admin-logs"
    Environment = var.environment
    Scenario    = "batch-submitjob"
    Purpose     = "batch-job-logs"
  }
}

# =============================================================================
# NETWORKING
# =============================================================================

# Egress-only security group — Batch Fargate tasks need outbound access to
# pull the amazon/aws-cli image and call AWS APIs. No inbound rules needed.
resource "aws_security_group" "batch_sg" {
  provider    = aws.prod
  name        = "pl-prod-batch-002-to-admin-sg"
  description = "Security group for Batch Fargate tasks - egress only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for image pulls and AWS API calls"
  }

  tags = {
    Name        = "pl-prod-batch-002-to-admin-sg"
    Environment = var.environment
    Scenario    = "batch-submitjob"
    Purpose     = "batch-security-group"
  }
}

# =============================================================================
# AWS BATCH COMPUTE ENVIRONMENT (Fargate)
# =============================================================================

resource "aws_batch_compute_environment" "ce" {
  provider                 = aws.prod
  name = "pl-prod-batch-002-to-admin-compute-env"
  type                     = "MANAGED"
  state                    = "ENABLED"

  compute_resources {
    type      = "FARGATE"
    max_vcpus = 4

    security_group_ids = [aws_security_group.batch_sg.id]
    subnets            = [var.subnet_id]
  }

  tags = {
    Name        = "pl-prod-batch-002-to-admin-compute-env"
    Environment = var.environment
    Scenario    = "batch-submitjob"
    Purpose     = "batch-compute-environment"
  }
}

# =============================================================================
# AWS BATCH JOB QUEUE
# =============================================================================

resource "aws_batch_job_queue" "queue" {
  provider = aws.prod
  name     = "pl-prod-batch-002-to-admin-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.ce.arn
  }

  tags = {
    Name        = "pl-prod-batch-002-to-admin-queue"
    Environment = var.environment
    Scenario    = "batch-submitjob"
    Purpose     = "batch-job-queue"
  }
}

# =============================================================================
# AWS BATCH JOB DEFINITION (Pre-existing with privileged jobRoleArn)
# =============================================================================

# This job definition represents a legitimate, pre-existing workflow that a
# developer created for a privileged maintenance task (e.g., automated IAM
# cleanup). It carries admin_role as the jobRoleArn.
#
# The default command ("echo", "operational-default") is a benign placeholder.
# The attacker does NOT need to register a new job definition — they submit a
# job against THIS definition with ContainerOverrides.Command set to their
# payload. Because the jobRoleArn is inherited from the job definition, the
# container receives AdministratorAccess credentials from the ECS metadata service.
resource "aws_batch_job_definition" "jd" {
  provider              = aws.prod
  name                  = "pl-prod-batch-002-to-admin-job-def"
  type                  = "container"
  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image            = "amazon/aws-cli:latest"
    command          = ["echo", "operational-default"]
    jobRoleArn       = aws_iam_role.admin_role.arn
    executionRoleArn = aws_iam_role.exec_role.arn
    resourceRequirements = [
      { type = "VCPU",   value = "0.25" },
      { type = "MEMORY", value = "512" }
    ]
    networkConfiguration = {
      assignPublicIp = "ENABLED"
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_logs.name
        "awslogs-stream-prefix" = "batch-002"
      }
    }
  })

  depends_on = [aws_cloudwatch_log_group.batch_logs]

  tags = {
    Name        = "pl-prod-batch-002-to-admin-job-def"
    Environment = var.environment
    Scenario    = "batch-submitjob"
    Purpose     = "pre-existing-privileged-job-definition"
  }
}

# =============================================================================
# CTF FLAG
# =============================================================================

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they
# reach administrator-equivalent permissions via the Batch job. The admin role
# attached to the container calls iam:AttachUserPolicy to give the starting user
# AdministratorAccess; the starting user then calls ssm:GetParameter to read
# the flag.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/batch-002-to-admin"
  description = "CTF flag for the batch-002-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-batch-002-to-admin-flag"
    Environment = var.environment
    Scenario    = "batch-submitjob"
    Purpose     = "ctf-flag"
  }
}
