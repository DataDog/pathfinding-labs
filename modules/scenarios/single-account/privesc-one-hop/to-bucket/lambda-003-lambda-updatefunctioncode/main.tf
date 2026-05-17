terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# lambda-updatefunctioncode to-bucket privilege escalation scenario
#
# This scenario demonstrates how a user with lambda:UpdateFunctionCode can modify
# an existing Lambda function's code to read sensitive S3 bucket contents using
# the function's pre-existing privileged execution role, then invoke the function
# to retrieve the flag from the response.

# Resource naming convention: pl-prod-lambda-003-to-bucket-{resource-type}
# Provider: aws.prod (single-account scenario)

# =============================================================================
# SCENARIO-SPECIFIC STARTING USER
# =============================================================================

# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band so
# destroy still succeeds if the user disables the scenario without first
# running cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-lambda-003-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-lambda-003-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-003-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationLambda"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:*:*:function:pl-prod-lambda-003-to-bucket-target-lambda"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:ListFunctions",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ROLE (PRE-EXISTING, ATTACHED TO LAMBDA)
# =============================================================================

# force_detach_policies = true is the role equivalent of force_destroy on
# aws_iam_user: it lets Terraform detach managed policies the demo may attach
# out-of-band so destroy succeeds without a prior cleanup run.
resource "aws_iam_role" "target_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-lambda-003-to-bucket-target-role"

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
    Name        = "pl-prod-lambda-003-to-bucket-target-role"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode"
    Purpose     = "target-role"
  }
}

# Grant the Lambda execution role read access to the sensitive bucket only.
# This is the privileged role the attacker hijacks by updating the function code.
resource "aws_iam_role_policy" "target_role_s3_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-003-to-bucket-target-role-s3-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadTargetBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Basic Lambda execution permissions (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "target_role_lambda_basic" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =============================================================================
# TARGET S3 BUCKET (SENSITIVE DATA)
# =============================================================================

resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-lambda-003-to-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-lambda-003-to-bucket-target-bucket"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode"
    Purpose     = "target-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive financial data that should only be accessible to authorized principals via proper IAM policies."

  tags = {
    Name        = "sensitive-data"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode"
    Purpose     = "sensitive-data"
  }
}

# CTF flag stored as an object in the target bucket. Retrieved by the attacker
# once they update the Lambda code to read it and invoke the function.
resource "aws_s3_object" "flag" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.target_bucket.id
  key          = "flag.txt"
  content      = var.flag_value
  content_type = "text/plain"

  tags = {
    Name        = "pl-prod-lambda-003-to-bucket-flag"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode"
    Purpose     = "ctf-flag"
  }
}

# =============================================================================
# PRE-EXISTING LAMBDA FUNCTION (BENIGN PLACEHOLDER CODE)
# =============================================================================

# Initial benign Lambda code — returns a static greeting.
# The attacker will replace this with code that reads flag.txt from the bucket
# via the execution role's S3 permissions, then invoke the function to get the flag.
data "archive_file" "initial_lambda" {
  type        = "zip"
  output_path = "/tmp/lambda-003-to-bucket-initial.zip"
  source {
    content  = "def lambda_handler(event, context):\n    return {'statusCode': 200, 'body': 'Hello from the original function'}\n"
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "target_function" {
  provider      = aws.prod
  function_name = "pl-prod-lambda-003-to-bucket-target-lambda"
  description   = "Pre-existing Lambda function with S3 read access used in the lambda-updatefunctioncode to-bucket scenario"
  role          = aws_iam_role.target_role.arn
  runtime       = "python3.12"
  handler       = "lambda_function.lambda_handler"

  filename         = data.archive_file.initial_lambda.output_path
  source_code_hash = data.archive_file.initial_lambda.output_base64sha256
  timeout          = 30

  # Environment variable lets the updated exploit code discover the bucket name
  # without hardcoding it, matching how a real attacker would use lambda:GetFunction
  # to enumerate the configuration before crafting the payload.
  environment {
    variables = {
      TARGET_BUCKET = aws_s3_bucket.target_bucket.id
    }
  }

  tags = {
    Name        = "pl-prod-lambda-003-to-bucket-target-lambda"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode"
    Purpose     = "target-lambda"
  }

  depends_on = [
    aws_iam_role_policy_attachment.target_role_lambda_basic
  ]
}
