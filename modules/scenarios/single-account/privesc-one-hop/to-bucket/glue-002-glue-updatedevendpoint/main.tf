terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# Glue UpdateDevEndpoint privilege escalation scenario
#
# This scenario demonstrates how a user with glue:UpdateDevEndpoint can add an SSH key
# to an existing Glue dev endpoint and gain access to sensitive S3 buckets with the
# endpoint's attached role permissions.

# Resource naming convention: pl-prod-glue-002-to-bucket-{resource-type}
# Provider: aws.prod (single-account scenario)

# =============================================================================
# SCENARIO-SPECIFIC STARTING USER
# =============================================================================

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-glue-002-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-glue-002-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "glue-updatedevendpoint"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy allowing UpdateDevEndpoint and discovery permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-002-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:UpdateDevEndpoint",
          "glue:GetDevEndpoint",
          "glue:GetDevEndpoints"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ROLE (ATTACHED TO DEV ENDPOINT)
# =============================================================================

resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-glue-002-to-bucket-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-glue-002-to-bucket-target-role"
    Environment = var.environment
    Scenario    = "glue-updatedevendpoint"
    Purpose     = "target-role"
  }
}

# Policy granting full access to the sensitive bucket
resource "aws_iam_role_policy" "target_role_s3_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-002-to-bucket-target-role-s3-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.sensitive_bucket.arn,
          "${aws_s3_bucket.sensitive_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Attach AWS managed policy for Glue service role
resource "aws_iam_role_policy_attachment" "target_role_glue_service" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# =============================================================================
# SENSITIVE S3 BUCKET
# =============================================================================

resource "aws_s3_bucket" "sensitive_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-glue-002-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-glue-002-bucket"
    Environment = var.environment
    Scenario    = "glue-updatedevendpoint"
    Purpose     = "target-bucket"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "sensitive_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload a test file with sensitive data
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is highly sensitive financial data that should only be accessible to authorized principals via proper IAM policies."
}

# =============================================================================
# PRE-EXISTING GLUE DEV ENDPOINT
# =============================================================================

# Note: This dev endpoint is created by Terraform and exists BEFORE the attack starts.
# It has NO public keys initially - the attacker will add their SSH key via UpdateDevEndpoint.

resource "aws_glue_dev_endpoint" "target_endpoint" {
  provider = aws.prod
  name     = "pl-prod-glue-002-to-bucket-endpoint"
  role_arn = aws_iam_role.target_role.arn

  # Glue version 1.0 (supports dev endpoints)
  glue_version = "1.0"

  # Minimum configuration: 2 DPU (Data Processing Units)
  number_of_nodes = 2

  # NO public keys - attacker will add them via UpdateDevEndpoint
  # public_key = "" # Intentionally omitted

  tags = {
    Name        = "pl-prod-glue-002-to-bucket-endpoint"
    Environment = var.environment
    Scenario    = "glue-updatedevendpoint"
    Purpose     = "vulnerable-endpoint"
  }
}
