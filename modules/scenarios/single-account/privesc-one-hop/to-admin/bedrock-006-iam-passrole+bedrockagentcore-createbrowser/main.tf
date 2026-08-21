terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Bedrock AgentCore Custom Browser Creation privilege escalation scenario (bedrock-006)
#
# This scenario demonstrates how a principal with iam:PassRole and Bedrock AgentCore
# Browser permissions can create a new Custom Browser backed by a privileged IAM role,
# then use CDP (Chrome DevTools Protocol) / Playwright to read temporary credentials
# from the browser's Firecracker MicroVM via the MicroVM Metadata Service (MMDS) at
# 169.254.169.254.
#
# The Custom Browser is NOT pre-provisioned by Terraform — the attacker creates it
# during the demo using bedrock-agentcore:CreateBrowser. Once the browser reaches
# READY state, the attacker calls StartBrowserSession to obtain a CDP WebSocket URL,
# then uses ConnectBrowserAutomationStream with a Playwright context.route hook that
# rewrites the MMDS token preflight request, allowing direct credential extraction.
#
# Unlike bedrock-003 (AgentRuntime) and bedrock-005 (Harness), the Custom Browser uses
# AWS-managed Chromium — no custom container image or ECR repository is required.
#
# Attack path:
#   starting_user
#     → iam:PassRole (scoped to target_role, conditioned on bedrock-agentcore.amazonaws.com)
#     + bedrock-agentcore:CreateBrowser
#     → new Custom Browser with admin execution role
#     → bedrock-agentcore:StartBrowserSession
#     → bedrock-agentcore:ConnectBrowserAutomationStream (CDP WebSocket)
#     → Playwright context.route hook rewrites MMDS token request
#     → read execution role credentials at 169.254.169.254
#     → ssm:GetParameter /pathfinding-labs/flags/bedrock-006-to-admin → CTF flag
#
# Resource naming convention: pl-prod-bedrock-006-to-admin-{purpose}

# ---------------------------------------------------------------------------
# Starting user
# ---------------------------------------------------------------------------

# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band so
# destroy still succeeds if the user disables the scenario without first
# running cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-bedrock-006-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-bedrock-006-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createbrowser"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the starting user exactly the permissions needed to exploit the path.
# Three statements:
#   1. RequiredForExploitationPassRole  — iam:PassRole scoped to the target role with a
#      service condition so it cannot be (mis)used against other services.
#   2. RequiredForExploitationBedrockAgentCore — the three AgentCore Browser actions the
#      exploit chain requires: CreateBrowser (provisions the browser with the passed role),
#      StartBrowserSession (obtains the CDP WebSocket URL), and
#      ConnectBrowserAutomationStream (opens the CDP stream used for credential extraction).
#   3. HelpfulForReconAndMonitoring — read-only IAM and AgentCore actions that let the
#      attacker discover available privileged roles and confirm browser readiness before
#      attempting to start a session.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-bedrock-006-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        # Scoped to the specific target role, not account root, so the permission
        # is narrow enough to remain realistic while still enabling the attack.
        Resource = aws_iam_role.target_role.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "bedrock-agentcore.amazonaws.com"
          }
        }
      },
      {
        Sid    = "RequiredForExploitationBedrockAgentCore"
        Effect = "Allow"
        Action = [
          # CreateBrowser provisions the Custom Browser with the passed execution role.
          # AWS-managed Chromium is used — no custom container image is required.
          "bedrock-agentcore:CreateBrowser",
          # StartBrowserSession returns the CDP WebSocket URL needed to connect.
          "bedrock-agentcore:StartBrowserSession",
          # ConnectBrowserAutomationStream opens the CDP stream; Playwright uses this
          # to install a context.route hook that rewrites the MMDS token preflight,
          # enabling direct credential extraction from 169.254.169.254.
          "bedrock-agentcore:ConnectBrowserAutomationStream"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          # Discover available privileged roles to choose as the execution role.
          "iam:ListRoles",
          # Inspect a role's trust policy to confirm it allows bedrock-agentcore.amazonaws.com.
          "iam:GetRole",
          # Confirm the browser reached READY state before calling StartBrowserSession.
          "bedrock-agentcore:GetBrowser"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Target role (pre-existing privileged execution role)
# ---------------------------------------------------------------------------

# This role represents the "privileged execution role" pre-condition from scenario.yaml:
# an IAM role with AdministratorAccess that trusts bedrock-agentcore.amazonaws.com.
# Terraform creates it as part of the vulnerable-state baseline so the attack path
# is immediately exploitable after apply.
#
# force_detach_policies = true is the role equivalent of force_destroy on aws_iam_user:
# it lets Terraform detach managed policies the demo may attach out-of-band so destroy
# succeeds without a prior cleanup run.
resource "aws_iam_role" "target_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-bedrock-006-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-bedrock-006-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createbrowser"
    Purpose     = "admin-target"
  }
}

resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ---------------------------------------------------------------------------
# CTF flag
# ---------------------------------------------------------------------------

# Stored in SSM Parameter Store. The attacker reads this parameter after
# extracting MMDS credentials from the browser's Firecracker MicroVM, using
# the admin role's temporary credentials. AdministratorAccess already grants
# ssm:GetParameter, so no additional IAM wiring is needed.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/bedrock-006-to-admin"
  description = "CTF flag for the bedrock-006-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-bedrock-006-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createbrowser"
    Purpose     = "ctf-flag"
  }
}
