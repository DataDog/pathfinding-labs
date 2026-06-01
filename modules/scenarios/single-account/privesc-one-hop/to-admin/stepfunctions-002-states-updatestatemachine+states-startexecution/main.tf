terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# states:UpdateStateMachine + states:StartExecution privilege escalation scenario
#
# This scenario demonstrates how a principal with states:UpdateStateMachine and
# states:StartExecution can replace an existing state machine's definition with
# malicious ASL that runs under the machine's pre-existing admin role — no
# iam:PassRole required. The existing role attachment is never changed, so AWS
# does not require the caller to prove PassRole.

# Resource naming convention: pl-prod-stepfunctions-002-to-admin-{resource-type}
# Provider: aws.prod (single account scenario)

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user.
# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band so
# destroy still succeeds if the user disables the scenario without first
# running cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-stepfunctions-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-stepfunctions-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "stepfunctions-002-states-updatestatemachine+states-startexecution"
    Purpose     = "starting-user"
  }
}

# Access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Inline policy for the starting user.
# Required permissions are scoped to the specific state machine ARN.
# Helpful recon permissions are grouped in a separate statement so that
# demo scripts can restrict them independently at runtime.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-stepfunctions-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationUpdateAndStart"
        Effect = "Allow"
        Action = [
          "states:UpdateStateMachine",
          "states:StartExecution"
        ]
        Resource = "arn:aws:states:*:${var.account_id}:stateMachine:pl-prod-stepfunctions-002-to-admin-statemachine"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "states:ListStateMachines",
          "states:DescribeStateMachine",
          "states:ListExecutions",
          "states:DescribeExecution"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# STATE MACHINE EXECUTION ROLE (Pre-existing privileged role)
# =============================================================================

# The state machine execution role already has AdministratorAccess.
# This represents the "pre-existing admin role" precondition documented in
# scenario.yaml — the attacker never changes roleArn on the state machine,
# so UpdateStateMachine does not trigger iam:PassRole checks.
# force_detach_policies = true lets Terraform destroy succeed even if the
# demo attaches additional policies out-of-band.
resource "aws_iam_role" "statemachine_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-stepfunctions-002-to-admin-statemachine-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-stepfunctions-002-to-admin-statemachine-role"
    Environment = var.environment
    Scenario    = "stepfunctions-002-states-updatestatemachine+states-startexecution"
    Purpose     = "statemachine-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "statemachine_role_admin" {
  provider   = aws.prod
  role       = aws_iam_role.statemachine_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# STATE MACHINE (Pre-existing victim resource)
# =============================================================================

# Pre-existing state machine with the privileged role already attached.
# Initial definition is a benign Pass state; the demo rewrites it via
# states:UpdateStateMachine with malicious ASL that calls iam:AttachUserPolicy.
# lifecycle.ignore_changes prevents Terraform from re-applying the benign
# definition after the demo has rewritten it.
resource "aws_sfn_state_machine" "statemachine" {
  provider = aws.prod
  name     = "pl-prod-stepfunctions-002-to-admin-statemachine"
  role_arn = aws_iam_role.statemachine_role.arn
  type     = "STANDARD"

  # Benign initial definition — no sensitive operations.
  # The demo will replace this with an ASL that calls iam:AttachUserPolicy.
  definition = jsonencode({
    Comment = "Benign initial definition — demo will replace this via UpdateStateMachine"
    StartAt = "Done"
    States = {
      Done = {
        Type   = "Pass"
        Result = "ok"
        End    = true
      }
    }
  })

  # Do not revert the definition if Terraform runs again after the demo has
  # replaced it. The demo_attack.sh script is the source of truth for the
  # malicious definition; cleanup_attack.sh restores the benign one.
  lifecycle {
    ignore_changes = [definition]
  }

  depends_on = [aws_iam_role_policy_attachment.statemachine_role_admin]

  tags = {
    Name        = "pl-prod-stepfunctions-002-to-admin-statemachine"
    Environment = var.environment
    Scenario    = "stepfunctions-002-states-updatestatemachine+states-startexecution"
    Purpose     = "vulnerable-statemachine"
  }
}

# =============================================================================
# CTF FLAG
# =============================================================================

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they
# reach administrator-equivalent permissions (AdministratorAccess grants
# ssm:GetParameter implicitly, so no extra IAM wiring is needed).
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/stepfunctions-002-to-admin"
  description = "CTF flag for the stepfunctions-002-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-stepfunctions-002-to-admin-flag"
    Environment = var.environment
    Scenario    = "stepfunctions-002-states-updatestatemachine+states-startexecution"
    Purpose     = "ctf-flag"
  }
}
