terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Lambda UpdateFunctionCode + InvokeFunction privilege escalation scenario (to-bucket)
#
# This scenario demonstrates how a user with lambda:UpdateFunctionCode and lambda:InvokeFunction
# can modify an existing Lambda function's code and immediately invoke it to execute malicious logic
# under the function's privileged execution role, gaining read access to a sensitive S3 bucket.
# The key difference from lambda-003 (UpdateFunctionCode-only) is that the attacker can manually
# trigger execution immediately rather than waiting for an automatic trigger.

# Resource naming convention: pl-prod-lambda-004-to-bucket-{resource-type}
# All resources use provider = aws.prod

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
  name          = "pl-prod-lambda-004-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-lambda-004-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-invokefunction"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the exploitable permissions to the starting user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-004-to-bucket-starting-user-policy"
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
# TARGET ROLE WITH S3 ACCESS
# =============================================================================

# Target role attached to the Lambda function — has read access to the sensitive bucket.
# force_detach_policies = true is the role equivalent of force_destroy on aws_iam_user:
# it lets Terraform detach managed policies the demo may attach out-of-band so
# destroy succeeds without a prior cleanup run.
resource "aws_iam_role" "target_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-lambda-004-to-bucket-target-role"

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
    Name        = "pl-prod-lambda-004-to-bucket-target-role"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-invokefunction"
    Purpose     = "target-role"
  }
}

# Policy granting the target role read access to the sensitive bucket
resource "aws_iam_role_policy" "target_role_s3_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-004-to-bucket-target-s3-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBucketRead"
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

# =============================================================================
# TARGET S3 BUCKET WITH SENSITIVE DATA AND CTF FLAG
# =============================================================================

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-lambda-004-to-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-lambda-004-to-bucket-target-bucket"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-invokefunction"
    Purpose     = "target-bucket"
  }
}

# Block public access (this is a private bucket)
resource "aws_s3_bucket_public_access_block" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Benign sensitive data file to make the bucket feel realistic
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data that should only be accessible to authorized principals."
}

# CTF flag stored as an S3 object in the target bucket. The attacker retrieves this after
# updating the Lambda function code to read the bucket and invoking it manually.
# Readable by any principal with s3:GetObject on this bucket (i.e., via the target role).
resource "aws_s3_object" "flag" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.target_bucket.id
  key          = "flag.txt"
  content      = var.flag_value
  content_type = "text/plain"

  tags = {
    Name        = "pl-prod-lambda-004-to-bucket-flag"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-invokefunction"
    Purpose     = "ctf-flag"
  }
}

# =============================================================================
# PRE-EXISTING TARGET LAMBDA FUNCTION
# =============================================================================

# Initial benign Lambda code. The attacker will replace this with exploit code
# that reads the flag from the target bucket using the function's privileged role.
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

# Pre-deployed Lambda function with benign code and a privileged execution role.
# This represents an existing production Lambda that the attacker will compromise
# by updating its code and invoking it to read the sensitive bucket.
resource "aws_lambda_function" "target_function" {
  provider      = aws.prod
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "pl-prod-lambda-004-to-bucket-target-lambda"
  role          = aws_iam_role.target_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 10

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    Name        = "pl-prod-lambda-004-to-bucket-target-lambda"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-invokefunction"
    Purpose     = "target-lambda"
  }
}
