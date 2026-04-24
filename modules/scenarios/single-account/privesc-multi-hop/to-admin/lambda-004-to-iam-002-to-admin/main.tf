# Multi-hop privilege escalation: Lambda UpdateFunctionCode + InvokeFunction -> IAM CreateAccessKey
#
# This scenario demonstrates a two-hop privilege escalation path:
# 1. Attacker updates Lambda function code and invokes it to exfiltrate the execution role credentials
# 2. Using the Lambda role's credentials, attacker creates access keys for an admin user
#
# Attack Path: starting_user -> (lambda:UpdateFunctionCode + lambda:InvokeFunction) ->
#              lambda_role credentials -> (iam:CreateAccessKey) -> admin_user -> admin access

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Resource naming convention: pl-prod-lambda-004-to-iam-002-{resource-type}
# All resources use provider = aws.prod

# =============================================================================
# STARTING USER (First principal in the attack chain)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-lambda-004-to-iam-002-starting-user"

  tags = {
    Name        = "pl-prod-lambda-004-to-iam-002-starting-user"
    Environment = var.environment
    Scenario    = "lambda-004-to-iam-002-to-admin"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with Lambda update and invoke permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-004-to-iam-002-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationUpdateFunctionCode"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode"
        ]
        Resource = aws_lambda_function.target_function.arn
      },
      {
        Sid    = "RequiredForExploitationInvokeFunction"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.target_function.arn
      }
    ]
  })
}

# =============================================================================
# TARGET LAMBDA FUNCTION (Second principal - execution environment)
# =============================================================================

# Pre-deployed Lambda function with benign code
# This represents an existing production Lambda that will be compromised
resource "aws_lambda_function" "target_function" {
  provider      = aws.prod
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "pl-prod-lambda-004-to-iam-002-target-function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    Name        = "pl-prod-lambda-004-to-iam-002-target-function"
    Environment = var.environment
    Scenario    = "lambda-004-to-iam-002-to-admin"
    Purpose     = "target-lambda"
  }
}

# Create the Lambda deployment package with benign code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = <<-EOT
      def lambda_handler(event, context):
          """Benign Lambda function for production use."""
          return {
              'statusCode': 200,
              'body': 'Production Lambda function executed successfully'
          }
    EOT
    filename = "lambda_function.py"
  }
}

# =============================================================================
# LAMBDA EXECUTION ROLE (Third principal - the privileged role)
# =============================================================================

# Lambda execution role with iam:CreateAccessKey permission
# This role can create access keys for the admin user
resource "aws_iam_role" "lambda_role" {
  provider = aws.prod
  name     = "pl-prod-lambda-004-to-iam-002-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-lambda-004-to-iam-002-lambda-role"
    Environment = var.environment
    Scenario    = "lambda-004-to-iam-002-to-admin"
    Purpose     = "lambda-execution-role"
  }
}

# Policy granting the Lambda role permission to create access keys for admin user
resource "aws_iam_role_policy" "lambda_role_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-004-to-iam-002-lambda-role-policy"
  role     = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationCreateAccessKey"
        Effect = "Allow"
        Action = [
          "iam:CreateAccessKey"
        ]
        Resource = aws_iam_user.admin_user.arn
      }
    ]
  })
}

# Basic Lambda execution permissions (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  provider   = aws.prod
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =============================================================================
# ADMIN USER (Fourth principal - the target)
# =============================================================================

# Admin user that will be the ultimate target of privilege escalation
# The attacker will create access keys for this user using the Lambda role's credentials
resource "aws_iam_user" "admin_user" {
  provider = aws.prod
  name     = "pl-prod-lambda-004-to-iam-002-admin-user"

  tags = {
    Name        = "pl-prod-lambda-004-to-iam-002-admin-user"
    Environment = var.environment
    Scenario    = "lambda-004-to-iam-002-to-admin"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the admin user
resource "aws_iam_user_policy_attachment" "admin_user_admin_access" {
  provider   = aws.prod
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/lambda-004-plus-iam-002-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-lambda-004-iam-002-to-admin-flag"
    Scenario = "lambda-004-to-iam-002-to-admin"
    Purpose  = "ctf-flag"
  }
}
