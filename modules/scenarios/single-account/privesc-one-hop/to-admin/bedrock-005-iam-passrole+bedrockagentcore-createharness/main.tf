terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Bedrock AgentCore Harness Creation privilege escalation scenario (bedrock-005)
#
# This scenario demonstrates how a principal with iam:PassRole and Bedrock AgentCore
# permissions can create a new Harness backed by a privileged IAM role, then extract
# temporary credentials from the MicroVM Metadata Service (MMDS) at 169.254.169.254.
#
# The Harness is NOT pre-provisioned by Terraform — the attacker creates it during the
# demo using bedrock-agentcore:CreateHarness (which internally triggers CreateAgentRuntime,
# CreateAgentRuntimeEndpoint, and CreateWorkloadIdentity). Once the Runtime is ACTIVE,
# the attacker calls InvokeAgentRuntimeCommand to run an arbitrary shell command inside
# the managed container and reads MMDS credentials for the passed admin role.
#
# Attack path:
#   starting_user
#     → iam:PassRole (scoped to target_role, conditioned on bedrock-agentcore.amazonaws.com)
#     + bedrock-agentcore:CreateHarness / CreateAgentRuntime / CreateAgentRuntimeEndpoint
#       / CreateWorkloadIdentity / GetAgentRuntime
#     → new Harness with admin execution role
#     → bedrock-agentcore:InvokeAgentRuntimeCommand
#     → curl 169.254.169.254 (MMDS) → extract admin credentials
#     → ssm:GetParameter /pathfinding-labs/flags/bedrock-005-to-admin → CTF flag
#
# Resource naming convention: pl-prod-bedrock-005-to-admin-{purpose}

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
  name          = "pl-prod-bedrock-005-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-bedrock-005-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createharness"
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
#   2. RequiredForExploitationBedrockAgentCore — all AgentCore create/get/invoke actions
#      the exploit chain requires.
#   3. HelpfulForReconAndMonitoring — read-only IAM actions that let the attacker discover
#      available privileged roles before choosing which one to pass.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-bedrock-005-to-admin-starting-user-policy"
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
          # CreateHarness is the top-level API; AWS internally sequences the
          # sub-calls below to provision the Runtime infrastructure and memory.
          "bedrock-agentcore:CreateHarness",
          "bedrock-agentcore:CreateAgentRuntime",
          "bedrock-agentcore:CreateAgentRuntimeEndpoint",
          "bedrock-agentcore:CreateWorkloadIdentity",
          # CreateMemory and GetMemory are called internally by CreateHarness as
          # part of managed-memory provisioning. No API opt-out exists in the
          # current SDK; the console's "disable memory" toggle maps to a nested
          # configuration field that the CLI SDK does not yet expose.
          "bedrock-agentcore:CreateMemory",
          "bedrock-agentcore:GetMemory",
          # GetAgentRuntime and GetHarness are called internally by CreateHarness
          # to poll the underlying runtime it provisions, and by the demo to wait
          # until the harness reaches READY before invoking it.
          "bedrock-agentcore:GetAgentRuntime",
          "bedrock-agentcore:GetHarness",
          # InvokeAgentRuntimeCommand is the exploit primitive — runs a shell
          # command inside the managed container that reads MMDS credentials.
          "bedrock-agentcore:InvokeAgentRuntimeCommand"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole"
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
  name                  = "pl-prod-bedrock-005-to-admin-target-role"

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
    Name        = "pl-prod-bedrock-005-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createharness"
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
# extracting MMDS credentials from the Harness container, using the admin
# role's temporary credentials. AdministratorAccess already grants
# ssm:GetParameter, so no additional IAM wiring is needed.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/bedrock-005-to-admin"
  description = "CTF flag for the bedrock-005-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-bedrock-005-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createharness"
    Purpose     = "ctf-flag"
  }
}
