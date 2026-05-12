terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# One-Hop to-Bucket: iam:CreateLoginProfile privilege escalation scenario
#
# This scenario demonstrates how an attacker with programmatic access can
# escalate privileges by creating a console password for another user who
# has S3 bucket access permissions.

# Resource naming convention: pl-prod-iam-004-bucket-{resource-type}

# ==============================================================================
# SCENARIO-SPECIFIC STARTING USER (ATTACKER)
# ==============================================================================

resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-iam-004-bucket-starting-user"

  tags = {
    Name        = "pl-prod-iam-004-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-createloginprofile-to-bucket"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user (programmatic access)
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Grant starting user permission to create login profile for hop1 user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-004-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationCreateLoginProfile"
        Effect = "Allow"
        Action = [
          "iam:CreateLoginProfile"
        ]
        Resource = aws_iam_user.hop1_user.arn
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:GetUser",
          "iam:GetLoginProfile"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# HOP1 USER (VICTIM WITH S3 BUCKET ACCESS)
# ==============================================================================

resource "aws_iam_user" "hop1_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-iam-004-bucket-hop1"

  tags = {
    Name        = "pl-prod-iam-004-bucket-hop1"
    Environment = var.environment
    Scenario    = "iam-createloginprofile-to-bucket"
    Purpose     = "victim-user-with-s3-access"
  }
}

# Grant hop1 user S3 permissions to access the sensitive bucket
resource "aws_iam_user_policy" "hop1_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-004-bucket-hop1-s3-policy"
  user     = aws_iam_user.hop1_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowListAllBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowReadSensitiveBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.sensitive_bucket.arn,
          "${aws_s3_bucket.sensitive_bucket.arn}/*"
        ]
      }
    ]
  })
}

# NOTE: We do NOT create a login profile here - that's what the attacker does!

# ==============================================================================
# TARGET S3 BUCKET WITH SENSITIVE DATA
# ==============================================================================

resource "aws_s3_bucket" "sensitive_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-iam-004-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-bucket"
    Environment = var.environment
    Scenario    = "iam-createloginprofile-to-bucket"
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

# Enable versioning
resource "aws_s3_bucket_versioning" "sensitive_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Upload a test file to demonstrate access
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data that should only be accessible to authorized principals. If you can read this after exploiting iam:CreateLoginProfile, the attack was successful!"
}

# CTF flag stored as an S3 object in the target bucket. The attacker retrieves this after
# successfully creating a console login profile for the hop1 user and using those credentials
# to read from the target bucket. Readable by any principal with s3:GetObject on this bucket.
resource "aws_s3_object" "flag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "flag.txt"
  content  = var.flag_value
}
