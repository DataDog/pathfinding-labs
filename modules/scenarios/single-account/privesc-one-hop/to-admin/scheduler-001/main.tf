terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + scheduler:CreateSchedule privilege escalation scenario
#
# This scenario demonstrates how an attacker with iam:PassRole and
# scheduler:CreateSchedule can create a one-shot EventBridge Scheduler schedule
# using the "universal target" ARN (arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy).
# The schedule fires as the passed admin role and calls iam:AttachUserPolicy,
# attaching AdministratorAccess to the attacker's starting user — no Lambda,
# no EC2, no additional infrastructure required.
#
# The universal target lets EventBridge Scheduler invoke any AWS SDK API directly,
# making PassRole+CreateSchedule equivalent in power to PassRole+Lambda for
# privilege escalation purposes, but with even less setup.
#
# Resource naming convention: pl-prod-scheduler-001-to-admin-{resource-type}
# Provider: aws.prod (single-account scenario)

# ── Scheduler admin role (prerequisite) ───────────────────────────────────────
# Trusts scheduler.amazonaws.com so EventBridge Scheduler can assume it when
# firing a schedule. Holds AdministratorAccess so the scheduled
# iam:AttachUserPolicy call has permission to succeed.
#
# force_detach_policies = true lets Terraform detach managed policies the demo
# may attach out-of-band so destroy succeeds without a prior cleanup run.
resource "aws_iam_role" "scheduler_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-scheduler-001-to-admin-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeSchedulerToAssume"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-scheduler-001-to-admin-scheduler-role"
    Environment = var.environment
    Scenario    = "scheduler-001"
    Purpose     = "admin-target"
  }
}

resource "aws_iam_role_policy_attachment" "scheduler_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.scheduler_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ── Starting principal (attacker) ─────────────────────────────────────────────
# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band (e.g.,
# the AdministratorAccess policy the schedule attaches as proof of escalation),
# so destroy succeeds if the user disables the scenario without first running
# cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-scheduler-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-scheduler-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "scheduler-001"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-scheduler-001-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # iam:PassRole scoped to the specific scheduler role — avoids giving the
        # attacker PassRole on * which would be far broader than the scenario needs.
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.scheduler_role.arn
      },
      {
        Sid    = "RequiredForExploitationCreateSchedule"
        Effect = "Allow"
        Action = [
          "scheduler:CreateSchedule"
        ]
        Resource = "*"
      },
      {
        # Helpful recon permissions: let the attacker discover roles trusting
        # scheduler.amazonaws.com and monitor schedule creation status.
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole",
          "scheduler:ListSchedules",
          "scheduler:GetSchedule"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── CTF flag ──────────────────────────────────────────────────────────────────
# Stored in SSM Parameter Store. The attacker retrieves this after the scheduled
# iam:AttachUserPolicy fires and they call ssm:GetParameter with their newly
# elevated starting user credentials. AdministratorAccess grants ssm:GetParameter
# implicitly — no extra IAM wiring is needed.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/scheduler-001-to-admin"
  description = "CTF flag for the scheduler-001-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-scheduler-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "scheduler-001"
    Purpose     = "ctf-flag"
  }
}
