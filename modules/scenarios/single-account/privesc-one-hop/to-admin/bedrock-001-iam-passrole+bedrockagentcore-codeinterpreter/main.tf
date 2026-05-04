terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Bedrock Code Interpreter privilege escalation scenario (bedrock-001)
#
# This scenario demonstrates how a principal with iam:PassRole and Bedrock AgentCore permissions
# can CREATE a new code interpreter with a privileged IAM role, then extract temporary credentials
# from the MicroVM Metadata Service (MMDS) at 169.254.169.254.
#
# Attack path: starting_user → (PassRole + CreateCodeInterpreter) → code interpreter with admin
# role → (StartSession + InvokeCodeInterpreter) → extract credentials from MMDS → admin access
#
# Resource naming convention: pl-prod-bedrock-001-to-admin-{resource-type}
# Scenario shorthand: "bci" (Bedrock Code Interpreter)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-bedrock-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-bedrock-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-codeinterpreter"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting starting user the ability to pass roles and create/use code interpreters
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-bedrock-001-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationPassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
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
          "bedrock-agentcore:CreateCodeInterpreter",
          "bedrock-agentcore:StartCodeInterpreterSession",
          "bedrock-agentcore:InvokeCodeInterpreter"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole",
          "bedrock-agentcore:GetCodeInterpreter"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target role with administrative permissions
# This role will be passed to the code interpreter during creation
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-bedrock-001-to-admin-target-role"

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
    Name        = "pl-prod-bedrock-001-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-codeinterpreter"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role
# When code interpreter is created with this role, it has full admin permissions
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CTF flag stored in SSM Parameter Store
# The attacker must obtain admin credentials and read this parameter to capture the flag
resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/bedrock-001-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name        = "pl-prod-bedrock-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-codeinterpreter"
    Purpose     = "ctf-flag"
  }
}
