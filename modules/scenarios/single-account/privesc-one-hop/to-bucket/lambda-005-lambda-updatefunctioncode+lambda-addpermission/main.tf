terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Lambda UpdateFunctionCode + AddPermission to-bucket privilege escalation scenario
#
# This scenario demonstrates how a user with lambda:UpdateFunctionCode and
# lambda:AddPermission can modify an existing Lambda function's code, grant
# themselves invoke permission via the resource-based policy, and read sensitive
# S3 bucket contents using the function's privileged execution role.
#
# Attack path:
#   starting_user
#     → lambda:UpdateFunctionCode (replace benign code with S3-reading payload)
#     → lambda:AddPermission (allow own user ARN to invoke the function)
#     → lambda:InvokeFunction (execute the payload)
#     → Lambda reads flag.txt from target bucket via lambda_exec_role
#     → sensitive bucket access / CTF flag

# Resource naming convention: pl-prod-lambda-005-to-bucket-{resource-type}
# Provider: aws.prod (single-account scenario)

# Get current region for scoping IAM resource ARNs
data "aws_region" "current" {
  provider = aws.prod
}

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
  name          = "pl-prod-lambda-005-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-lambda-005-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-addpermission"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the exact permissions needed to exploit this scenario plus
# recon-only permissions that make manual exploitation easier.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-005-to-bucket-starting-user-policy"
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
        Resource = "arn:aws:lambda:${data.aws_region.current.id}:${var.account_id}:function:pl-prod-lambda-005-to-bucket-target-lambda"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:GetPolicy",
          "lambda:ListFunctions"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# LAMBDA EXECUTION ROLE (pre-existing privileged role)
# =============================================================================

# force_detach_policies = true is the role equivalent of force_destroy on
# aws_iam_user: it lets Terraform detach managed policies the demo may
# attach out-of-band so destroy succeeds without a prior cleanup run.
resource "aws_iam_role" "lambda_exec_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-lambda-005-to-bucket-lambda-exec-role"

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
    Name        = "pl-prod-lambda-005-to-bucket-lambda-exec-role"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-addpermission"
    Purpose     = "lambda-execution-role"
  }
}

# Grant the Lambda execution role read access to the target bucket.
# This is the privilege the attacker indirectly exploits — they cannot
# assume this role directly but can execute code under it via Lambda.
resource "aws_iam_role_policy" "lambda_exec_role_s3_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-005-to-bucket-lambda-exec-role-s3-policy"
  role     = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationS3"
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
# TARGET S3 BUCKET WITH SENSITIVE DATA
# =============================================================================

resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-lambda-005-to-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-lambda-005-to-bucket-target-bucket"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-addpermission"
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

# Benign sensitive-data file to make the bucket look realistic
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is highly sensitive data that should only be accessible to authorized principals via proper IAM policies."

  tags = {
    Name        = "pl-prod-lambda-005-to-bucket-sensitive-data"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-addpermission"
    Purpose     = "sensitive-data"
  }
}

# CTF flag stored as an S3 object. Retrieved by the attacker once they
# successfully invoke the modified Lambda — no extra IAM is required
# since the lambda_exec_role already has s3:GetObject on this bucket.
resource "aws_s3_object" "flag" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.target_bucket.id
  key          = "flag.txt"
  content      = var.flag_value
  content_type = "text/plain"

  tags = {
    Name        = "pl-prod-lambda-005-to-bucket-flag"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-addpermission"
    Purpose     = "ctf-flag"
  }
}

# =============================================================================
# PRE-EXISTING TARGET LAMBDA FUNCTION
# =============================================================================

# Placeholder Lambda code deployed at scenario setup time. The function is
# intentionally benign — it just returns a static greeting. The attacker
# will replace this code with a payload that reads flag.txt from the bucket.
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

# The Lambda's resource-based policy starts empty — the starting_user has
# NO invoke permission at setup time. The attacker must call AddPermission
# to grant themselves invoke access before they can run their payload.
resource "aws_lambda_function" "target_lambda" {
  provider         = aws.prod
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "pl-prod-lambda-005-to-bucket-target-lambda"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30

  # Explicit dependency so the role policy exists before the function is created
  depends_on = [aws_iam_role_policy.lambda_exec_role_s3_policy]

  tags = {
    Name        = "pl-prod-lambda-005-to-bucket-target-lambda"
    Environment = var.environment
    Scenario    = "lambda-updatefunctioncode+lambda-addpermission"
    Purpose     = "target-lambda"
  }
}
