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
# CTF-002: AI Chatbot Prompt Injection → Lambda Pivot → Admin
#
# Same vulnerable chatbot as ctf-001, but the chatbot role is NOT admin.
# Instead it has limited Lambda permissions: list, update code, and invoke.
#
# A second "Acme Data Processor" Lambda runs with AdministratorAccess.
# The attack chain:
#   1. Prompt injection on chatbot → chatbot role creds (limited Lambda perms)
#   2. ListFunctions → discover pl-prod-ctf-002-acme-data-processor (admin role)
#   3. UpdateFunctionCode → replace benign code with credential-exfiltrating code
#   4. InvokeFunction → admin creds returned in response
#   5. ssm:GetParameter → flag
#
# Resource naming: pl-prod-ctf-002-{resource-type}
# =============================================================================

# ---- CHATBOT RESOURCES -------------------------------------------------------

# Chatbot execution role - LIMITED permissions only (not admin)
resource "aws_iam_role" "chatbot_role" {
  provider = aws.prod
  name     = "pl-prod-ctf-002-chatbot-role"

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
    Name        = "pl-prod-ctf-002-chatbot-role"
    Environment = var.environment
    Scenario    = "ctf-002-ai-chatbot-lambda-pivot"
    Purpose     = "chatbot-execution-role"
  }
}

# Limited Lambda permissions - enough to pivot to the privileged target Lambda
resource "aws_iam_role_policy" "chatbot_role_policy" {
  provider = aws.prod
  name     = "pl-prod-ctf-002-chatbot-policy"
  role     = aws_iam_role.chatbot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitation"
        Effect = "Allow"
        Action = [
          "lambda:ListFunctions",
          "lambda:UpdateFunctionCode",
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForDiscovery"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "sts:GetCallerIdentity",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM read-only - lets the player enumerate roles, policies, and use
# iam:SimulatePrincipalPolicy to figure out which Lambda role is worth targeting
resource "aws_iam_role_policy_attachment" "chatbot_iam_readonly" {
  provider   = aws.prod
  role       = aws_iam_role.chatbot_role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

# Basic execution for CloudWatch logging
resource "aws_iam_role_policy_attachment" "chatbot_basic_exec" {
  provider   = aws.prod
  role       = aws_iam_role.chatbot_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# The vulnerable chatbot Lambda (same code as ctf-001, limited role)
resource "aws_lambda_function" "chatbot" {
  provider      = aws.prod
  filename      = "${path.module}/lambda/chatbot/chatbot.zip"
  function_name = "pl-prod-ctf-002-acmebot"
  role          = aws_iam_role.chatbot_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 30
  memory_size   = 256

  source_code_hash = filebase64sha256("${path.module}/lambda/chatbot/chatbot.zip")

  # No environment variables - OpenAI key is provided per-request via the UI (BYOK)

  tags = {
    Name        = "pl-prod-ctf-002-acmebot"
    Environment = var.environment
    Scenario    = "ctf-002-ai-chatbot-lambda-pivot"
    Purpose     = "vulnerable-chatbot"
  }
}

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

# ---- TARGET LAMBDA RESOURCES -------------------------------------------------

# Target Lambda execution role - AdministratorAccess
# This is the escalation target: a production data processor with admin rights.
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-ctf-002-target-role"

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
    Name        = "pl-prod-ctf-002-target-role"
    Environment = var.environment
    Scenario    = "ctf-002-ai-chatbot-lambda-pivot"
    Purpose     = "target-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "target_admin" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "target_basic_exec" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# The privileged target Lambda - benign data processor that will be compromised
resource "aws_lambda_function" "target" {
  provider      = aws.prod
  filename      = "${path.module}/lambda/target/target.zip"
  function_name = "pl-prod-ctf-002-acme-data-processor"
  role          = aws_iam_role.target_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 10
  memory_size   = 128

  source_code_hash = filebase64sha256("${path.module}/lambda/target/target.zip")

  tags = {
    Name        = "pl-prod-ctf-002-acme-data-processor"
    Environment = var.environment
    Scenario    = "ctf-002-ai-chatbot-lambda-pivot"
    Purpose     = "target-lambda-admin-role"
  }

  # Ignore code changes - the attacker will update this function's code during the CTF.
  # terraform apply after cleanup will restore the original code via source_code_hash.
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# ---- SHARED RESOURCES --------------------------------------------------------

# The flag - readable only with admin credentials
resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/ctf-002-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name        = "ctf-002-flag"
    Environment = var.environment
    Scenario    = "ctf-002-ai-chatbot-lambda-pivot"
  }
}

# Starting user for CLI-based participants
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ctf-002-starting-user"

  tags = {
    Name        = "pl-prod-ctf-002-starting-user"
    Environment = var.environment
    Scenario    = "ctf-002-ai-chatbot-lambda-pivot"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ctf-002-starting-user-policy"
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
          "iam:GetUser",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      }
    ]
  })
}
