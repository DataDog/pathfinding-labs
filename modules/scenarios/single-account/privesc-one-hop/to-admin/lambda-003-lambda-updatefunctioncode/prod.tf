terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Lambda UpdateFunctionCode privilege escalation scenario
#
# This scenario demonstrates how a user with lambda:UpdateFunctionCode and lambda:InvokeFunction
# can modify an existing Lambda function's code to execute malicious logic under the function's
# privileged execution role, gaining admin access.

# Resource naming convention: pl-prod-lambda-003-to-admin-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-lambda-003-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-lambda-003-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with Lambda update permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-003-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationLambda"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:InvokeFunction",
        ]
        Resource = aws_lambda_function.target_function.arn
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:ListFunctions",
          "iam:GetRole",
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role (target of privilege escalation)
# This role is attached to the Lambda function
resource "aws_iam_role" "target_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-lambda-003-to-admin-target-role"

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
    Name        = "pl-prod-lambda-003-to-admin-target-role"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode"
    Purpose     = "admin-target"
  }
}

# Attach administrator access to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Pre-deployed Lambda function with benign code
# This represents an existing production Lambda that will be compromised
resource "aws_lambda_function" "target_function" {
  provider      = aws.prod
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "pl-prod-lambda-003-to-admin-target-lambda"
  role          = aws_iam_role.target_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 10

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    Name        = "pl-prod-lambda-003-to-admin-target-lambda"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode"
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

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/lambda-003-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-lambda-003-to-admin-flag"
    Scenario = "lambda-003-lambda-updatefunctioncode"
    Purpose  = "ctf-flag"
  }
}
