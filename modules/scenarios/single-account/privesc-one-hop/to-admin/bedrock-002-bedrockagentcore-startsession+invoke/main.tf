terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Bedrock Code Interpreter privilege escalation scenario (bedrock-002)
#
# This scenario demonstrates how a principal with bedrock-agentcore:StartCodeInterpreterSession
# and bedrock-agentcore:InvokeCodeInterpreter can access an EXISTING code interpreter that has
# a privileged IAM role attached, then extract temporary credentials from the MicroVM Metadata
# Service (MMDS) at 169.254.169.254.
#
# Unlike bedrock-001 (which creates a NEW interpreter), this scenario targets a PRE-DEPLOYED
# code interpreter that already has admin permissions through its execution role.
#
# Attack path: starting_user → (StartCodeInterpreterSession) → existing code interpreter with
# admin role → (InvokeCodeInterpreter) → extract credentials from MMDS → admin access
#
# Resource naming convention: pl-prod-bedrock-002-to-admin-{resource-type}
# Scenario shorthand: "bedrock-002" (Pathfinding.cloud ID)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-bedrock-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-bedrock-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "bedrockagentcore-startsession+invoke"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting starting user the ability to start sessions with and invoke
# existing code interpreters (but NOT create new ones or pass roles)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-bedrock-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationCodeInterpreter"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:StartCodeInterpreterSession",
          "bedrock-agentcore:InvokeCodeInterpreter"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:ListCodeInterpreters",
          "bedrock-agentcore:GetCodeInterpreter"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target role with administrative permissions
# This role is assumed by the code interpreter and provides the escalation target
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-bedrock-002-to-admin-target-role"

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
    Name        = "pl-prod-bedrock-002-to-admin-target-role"
    Environment = var.environment
    Scenario    = "bedrockagentcore-startsession+invoke"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role
# When code interpreter runs with this role, it has full admin permissions
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CTF flag stored in SSM Parameter Store — readable only after gaining admin access
resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/bedrock-002-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name        = "pl-prod-bedrock-002-to-admin-flag"
    Environment = var.environment
    Scenario    = "bedrockagentcore-startsession+invoke"
    Purpose     = "ctf-flag"
  }
}

# Pre-deployed code interpreter with the privileged execution role
# This is the EXISTING resource that the attacker will target
# Note: Using underscores in name per AWS Bedrock API requirements
resource "aws_bedrockagentcore_code_interpreter" "existing_interpreter" {
  provider = aws.prod
  name     = "pl_prod_bedrock_002_to_admin_target_interpreter"

  execution_role_arn = aws_iam_role.target_role.arn

  network_configuration {
    network_mode = "SANDBOX"
  }

  tags = {
    Name        = "pl-prod-bedrock-002-to-admin-target-interpreter"
    Environment = var.environment
    Scenario    = "bedrockagentcore-startsession+invoke"
    Purpose     = "existing-interpreter-with-admin-role"
  }
}
