terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# =============================================================================
# CTF-001: AI Chatbot Prompt Injection to Admin
#
# A "helpful" internal engineering assistant Lambda backed by OpenAI.
# A developer gave it a run_command tool for server diagnostics without
# restricting what commands it can run, then attached an admin execution role.
# Prompt injection → arbitrary shell execution → env vars → admin credentials.
#
# Resource naming: pl-prod-ctf-001-{resource-type}
# =============================================================================

# Lambda execution role - AdministratorAccess
# This is the misconfiguration: a chatbot role with full admin permissions.
resource "aws_iam_role" "chatbot_role" {
  provider = aws.prod
  name     = "pl-prod-ctf-001-chatbot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-ctf-001-chatbot-role"
    Environment = var.environment
    Scenario    = "ctf-001-ai-chatbot-to-admin"
    Purpose     = "chatbot-execution-role"
  }
}

# AdministratorAccess - the intentional misconfiguration
resource "aws_iam_role_policy_attachment" "chatbot_admin" {
  provider   = aws.prod
  role       = aws_iam_role.chatbot_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Basic execution for CloudWatch logging
resource "aws_iam_role_policy_attachment" "chatbot_basic_exec" {
  provider   = aws.prod
  role       = aws_iam_role.chatbot_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# The vulnerable chatbot Lambda
resource "aws_lambda_function" "chatbot" {
  provider      = aws.prod
  filename      = "${path.module}/lambda/chatbot/chatbot.zip"
  function_name = "pl-prod-ctf-001-acmebot"
  role          = aws_iam_role.chatbot_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 30
  memory_size   = 256

  source_code_hash = filebase64sha256("${path.module}/lambda/chatbot/chatbot.zip")

  # No environment variables - OpenAI key is provided per-request via the UI (BYOK)

  tags = {
    Name        = "pl-prod-ctf-001-acmebot"
    Environment = var.environment
    Scenario    = "ctf-001-ai-chatbot-to-admin"
    Purpose     = "vulnerable-chatbot"
  }
}

# Public Lambda Function URL - serves both the HTML UI and the chat API
resource "aws_lambda_function_url" "chatbot_url" {
  provider           = aws.prod
  function_name      = aws_lambda_function.chatbot.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST"]
    allow_headers     = ["content-type"]
    max_age           = 86400
  }
}

# The flag - readable only with admin credentials
# AdministratorAccess grants ssm:GetParameter.
# The starting user has no ssm:* permissions.
resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/ctf-001-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name        = "ctf-001-flag"
    Environment = var.environment
    Scenario    = "ctf-001-ai-chatbot-to-admin"
  }
}

# Starting user - CLI-based participants use these credentials to enumerate the account
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ctf-001-starting-user"

  tags = {
    Name        = "pl-prod-ctf-001-starting-user"
    Environment = var.environment
    Scenario    = "ctf-001-ai-chatbot-to-admin"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Minimal starting permissions: enough to discover the Lambda and its URL,
# but not enough to invoke it via AWS SDK or read the flag.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ctf-001-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HelpfulForDiscovery"
        Effect = "Allow"
        Action = [
          "lambda:ListFunctions",
          "lambda:GetFunction",
          "lambda:GetFunctionUrlConfig",
          "sts:GetCallerIdentity",
          "iam:GetUser"
        ]
        Resource = "*"
      }
    ]
  })
}
