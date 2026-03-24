terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + glue:CreateDevEndpoint privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and glue:CreateDevEndpoint
# can create a Glue development endpoint with a privileged role that has S3 access,
# then SSH into the endpoint and use the role's credentials to access sensitive buckets.

# Resource naming convention: pl-{environment}-glue-001-to-bucket-{resource-type}
# All resources use provider = aws.prod

# =============================================================================
# SCENARIO-SPECIFIC STARTING USER
# =============================================================================

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-glue-001-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-glue-001-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createdevendpoint"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the exploitable permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-001-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "RequiredForExploitationGlue"
        Effect = "Allow"
        Action = [
          "glue:CreateDevEndpoint"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ROLE WITH S3 ACCESS
# =============================================================================

# Target role that will be passed to Glue (has S3 bucket access)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-glue-001-to-bucket-target-role"

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
    Name        = "pl-prod-glue-001-to-bucket-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createdevendpoint"
    Purpose     = "target-role"
  }
}

# Attach policy granting full access to the sensitive S3 bucket
resource "aws_iam_role_policy" "target_role_s3_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-001-to-bucket-target-s3-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.sensitive_bucket.arn,
          "${aws_s3_bucket.sensitive_bucket.arn}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# TARGET S3 BUCKET WITH SENSITIVE DATA
# =============================================================================

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "sensitive_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-glue-001-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-glue-001-bucket"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createdevendpoint"
    Purpose     = "target-bucket"
  }
}

# Block public access (this is a private bucket)
resource "aws_s3_bucket_public_access_block" "sensitive_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload a test file to demonstrate access
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data that should only be accessible to authorized principals."
}
