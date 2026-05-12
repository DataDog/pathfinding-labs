terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + states:CreateStateMachine + states:StartExecution privilege escalation scenario
#
# This scenario demonstrates how an attacker with iam:PassRole, states:CreateStateMachine,
# and states:StartExecution permissions can escalate privileges by creating a Step Functions
# state machine that calls IAM APIs (e.g., iam:AttachUserPolicy) using an admin role,
# effectively granting themselves AdministratorAccess.

# Resource naming convention: pl-prod-stepfunctions-001-to-admin-{resource-type}
# Provider: aws.prod (single account scenario)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-stepfunctions-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-stepfunctions-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "stepfunctions-001-iam-passrole+states-createstatemachine+states-startexecution"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (PassRole + Step Functions permissions)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-stepfunctions-001-to-admin-starting-user-policy"
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
        Resource = aws_iam_role.admin_role.arn
      },
      {
        Sid    = "RequiredForExploitationStepFunctions"
        Effect = "Allow"
        Action = [
          "states:CreateStateMachine",
          "states:StartExecution"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role that will be passed to Step Functions
# Step Functions assumes this role to execute state machine tasks (AWS SDK integrations),
# which means the state machine can call any AWS API that this role has permissions for.
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-stepfunctions-001-to-admin-admin-role"

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
    Name        = "pl-prod-stepfunctions-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "stepfunctions-001-iam-passrole+states-createstatemachine+states-startexecution"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
