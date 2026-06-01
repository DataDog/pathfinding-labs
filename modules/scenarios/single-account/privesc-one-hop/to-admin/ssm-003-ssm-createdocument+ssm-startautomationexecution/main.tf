terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# PassRole + SSM Automation ExecuteScript to Admin privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, ssm:CreateDocument,
# and ssm:StartAutomationExecution can escalate to full administrator by creating
# a custom SSM Automation document containing an aws:executeScript step that runs
# Python inline. The attacker passes an admin-privileged IAM role as the
# AutomationAssumeRole parameter; SSM assumes that role and runs the script in
# AWS-managed serverless compute — no EC2 instance, SSM agent, or pre-existing
# Lambda function required. The Python script calls iam:AttachUserPolicy to grant
# AdministratorAccess to the starting user's own identity.

# Resource naming convention: pl-prod-ssm-003-to-admin-{resource-type}

# ==============================================================================
# SCENARIO-SPECIFIC STARTING USER
# ==============================================================================

# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band so
# destroy still succeeds if the user disables the scenario without first
# running cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-ssm-003-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ssm-003-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "ssm-createdocument+ssm-startautomationexecution"
    Purpose     = "starting-user"
  }
}

# Access keys for the starting user (consumed by demo_attack.sh via Terraform outputs)
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Inline policy granting the three permissions required for exploitation.
# iam:PassRole is scoped to the automation role ARN and conditioned on
# iam:PassedToService = ssm.amazonaws.com, matching exactly what SSM
# checks at start-automation-execution time.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ssm-003-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.automation_role.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ssm.amazonaws.com"
          }
        }
      },
      {
        Sid    = "RequiredForExploitationSSMAutomation"
        Effect = "Allow"
        Action = [
          "ssm:CreateDocument",
          "ssm:StartAutomationExecution",
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole",
          "ssm:ListDocuments",
          "ssm:DescribeDocument",
          "ssm:GetAutomationExecution",
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# AUTOMATION ROLE (PASSED AS AutomationAssumeRole — TARGET PRIVILEGE LEVEL)
# ==============================================================================

# This role is passed to SSM Automation via the AutomationAssumeRole parameter.
# SSM's service principal assumes it, then runs the aws:executeScript Python step
# with this role's credentials (AdministratorAccess). The Python script calls
# iam:AttachUserPolicy on the starting user, granting it AdministratorAccess.
#
# force_detach_policies = true is the role equivalent of force_destroy on
# aws_iam_user: it lets Terraform detach managed policies the demo may
# attach out-of-band so destroy succeeds without a prior cleanup run.
resource "aws_iam_role" "automation_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-ssm-003-to-admin-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-ssm-003-to-admin-automation-role"
    Environment = var.environment
    Scenario    = "ssm-createdocument+ssm-startautomationexecution"
    Purpose     = "automation-role"
  }
}

# Attach AdministratorAccess so that the aws:executeScript step can call
# iam:AttachUserPolicy (and any other IAM action needed) on behalf of SSM.
resource "aws_iam_role_policy_attachment" "automation_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.automation_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ==============================================================================
# CTF FLAG
# ==============================================================================

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they
# gain AdministratorAccess via the escalation (AdministratorAccess grants
# ssm:GetParameter implicitly, so no extra IAM wiring is needed).
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/ssm-003-to-admin"
  description = "CTF flag for the ssm-003-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-ssm-003-to-admin-flag"
    Environment = var.environment
    Scenario    = "ssm-createdocument+ssm-startautomationexecution"
    Purpose     = "ctf-flag"
  }
}
