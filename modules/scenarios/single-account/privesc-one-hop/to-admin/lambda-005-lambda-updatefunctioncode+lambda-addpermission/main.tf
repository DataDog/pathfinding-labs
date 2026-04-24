terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# Lambda UpdateFunctionCode + AddPermission privilege escalation scenario
#
# This scenario demonstrates how a user with lambda:UpdateFunctionCode and lambda:AddPermission
# can modify existing Lambda function code, add permission to invoke it, and execute malicious
# code under the function's privileged role to gain admin access

# Resource naming convention: pl-prod-lambda-005-to-admin-{resource-type}

# Get current region
data "aws_region" "current" {
  provider = aws.prod
}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-lambda-005-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-lambda-005-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-addpermission"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with Lambda permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-005-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationLambda"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:AddPermission"
        ]
        Resource = "arn:aws:lambda:${data.aws_region.current.id}:${var.account_id}:function:pl-prod-lambda-005-to-admin-target-lambda"
      }
    ]
  })
}

# Lambda execution role with admin access (the target role to exploit)
resource "aws_iam_role" "lambda_exec_role" {
  provider = aws.prod
  name     = "pl-prod-lambda-005-to-admin-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-lambda-005-to-admin-lambda-exec-role"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-addpermission"
    Purpose     = "lambda-execution-role"
  }
}

# Attach AdministratorAccess to the Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_exec_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create a ZIP file with a basic Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = <<-EOT
      def lambda_handler(event, context):
          return {
              'statusCode': 200,
              'body': 'Hello from Lambda!'
          }
    EOT
    filename = "lambda_function.py"
  }
}

# Target Lambda function that will be exploited
resource "aws_lambda_function" "target_lambda" {
  provider         = aws.prod
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "pl-prod-lambda-005-to-admin-target-lambda"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"

  tags = {
    Name        = "pl-prod-lambda-005-to-admin-target-lambda"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-addpermission"
    Purpose     = "target-lambda"
  }
}

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/lambda-005-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-lambda-005-to-admin-flag"
    Scenario = "lambda-005-lambda-updatefunctioncode+lambda-addpermission"
    Purpose  = "ctf-flag"
  }
}
